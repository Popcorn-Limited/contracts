// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";
import {IERC4626, IERC20} from "../interfaces/vault/IVault.sol";

/**
 * @title   BaseStrategy
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
abstract contract BaseStrategy is
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnedUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @notice Initialize a new Adapter.
     * @param popERC4626InitData Encoded data for the base adapter initialization.
     * @dev `asset` - The underlying asset
     * @dev `_owner` - Owner of the contract. Controls management functions.
     * @dev `_strategy` - An optional strategy to enrich the adapter with additional functionality.
     * @dev `_harvestCooldown` - Cooldown period between harvests.
     * @dev `_requiredSigs` - Function signatures required by the strategy (EIP-165)
     * @dev `_strategyConfig` - Additional data which can be used by the strategy on `harvest()`
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Each Adapter implementation should implement checks to make sure that the adapter is wrapping the underlying protocol correctly.
     * @dev If a strategy is provided, it will be verified to make sure it implements the required functions.
     */
    function __BaseStrategy_init(
        address asset_,
        address owner_,
    ) internal onlyInitializing {
        __Owned_init(owner_);
        __Pausable_init();
        __ERC4626_init(IERC20Metadata(asset_));

        lastHarvest = block.timestamp;
        autoHarvest = true;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error InvalidReceiver();
    error MaxError(uint256 amount);

    function deposit(uint256 assets) public returns (uint256) {
        return deposit(assets, msg.sender);
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    function withdraw(uint256 assets) public returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override takeFees {
        if (shares == 0 || assets == 0) revert ZeroAmount();

        // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            caller,
            address(this),
            assets
        );

        _protocolDeposit(assets, shares);

        _mint(receiver, shares);

        if(autoHarvest) harvest();

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override takeFees {
        if (shares == 0 || assets == 0) revert ZeroAmount();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        if (paused()) {
            IERC20(asset()).safeTransfer(receiver, assets);
        } else {
            _protocolWithdraw(assets, shares, receiver);
        }

        if(autoHarvest) harvest();

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total amount of underlying `asset` token managed by adapter.
     * @dev Return assets held by adapter if paused.
     */
    function totalAssets() public view override returns (uint256) {
        return
            paused()
                ? IERC20(asset()).balanceOf(address(this))
                : _totalAssets();
    }

    /**
     * @notice Total amount of underlying `asset` token managed by adapter through the underlying protocol.
     */
    function _totalAssets() internal view virtual returns (uint256) {}

    /**
     * @notice Convert either `assets` or `shares` into underlying shares.
     * @dev This is an optional function for underlying protocols that require deposit/withdrawal amounts in their shares.
     * @dev Returns shares if totalSupply is 0.
     */
    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view virtual returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function maxDeposit(
        address
    ) public view virtual override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /**
     * @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function maxMint(address) public view virtual override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /*//////////////////////////////////////////////////////////////
                      FEE LOGIC
  //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;
    uint256 public highWaterMark;

    address public constant FEE_RECIPIENT =
        address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);

    error InvalidPerformanceFee(uint256 fee);

    /**
     * @notice Performance fee that has accrued since last fee harvest.
     * @return Accrued performance fee in underlying `asset` token.
     * @dev Performance fee is based on a high water mark value. If vault share value has increased above the
     *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
     */
    function accruedPerformanceFee() public view returns (uint256) {
        uint256 highWaterMark_ = highWaterMark;
        uint256 shareValue = convertToAssets(1e18);
        uint256 performanceFee_ = performanceFee;

        return
            performanceFee_ > 0 && shareValue > highWaterMark_
                ? performanceFee_.mulDiv(
                    (shareValue - highWaterMark_) * totalSupply(),
                    1e36,
                    Math.Rounding.Floor
                )
                : 0;
    }

    /**
     * @notice Set a new performance fee for this adapter. Caller must be owner.
     * @param newFee performance fee in 1e18.
     * @dev Fees can be 0 but never more than 2e17 (1e18 = 100%, 1e14 = 1 BPS)
     */
    function setPerformanceFee(uint256 newFee) public onlyOwner {
        // Dont take more than 20% performanceFee
        if (newFee > 2e17) revert InvalidPerformanceFee(newFee);

        emit PerformanceFeeChanged(performanceFee, newFee);

        performanceFee = newFee;
    }

    /// @notice Collect performance fees and update asset checkpoint.
    modifier takeFees() {
        _;
        uint256 fee = accruedPerformanceFee();
        uint256 shareValue = convertToAssets(1e18);

        if (shareValue > highWaterMark) highWaterMark = shareValue;

        if (fee > 0) _mint(FEE_RECIPIENT, convertToShares(fee));
    }

    /*//////////////////////////////////////////////////////////////
                      PAUSING LOGIC
  //////////////////////////////////////////////////////////////*/

    /// @notice Pause Deposits and withdraw all funds from the underlying protocol. Caller must be owner.
    function pause() external onlyOwner {
        _protocolWithdraw(totalAssets(), totalSupply());
        _pause();
    }

    /// @notice Unpause Deposits and deposit all funds into the underlying protocol. Caller must be owner.
    function unpause() external onlyOwner {
        _protocolDeposit(totalAssets(), totalSupply());
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit into the underlying protocol.
    function _protocolDeposit(uint256 assets, uint256 shares) internal virtual {
        // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
    }

    /// @notice Withdraw from the underlying protocol.
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares,
        address recipient
    ) internal virtual {
        // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
    }

        /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvest() public virtual takeFees {
        }

    function toggleAutoHarvest() external onlyOwner {
        emit AutoHarvestToggled(autoHarvest, !autoHarvest);
        autoHarvest = !autoHarvest;
    }


    /*//////////////////////////////////////////////////////////////
                      EIP-2612 LOGIC
  //////////////////////////////////////////////////////////////*/

    //  EIP-2612 STORAGE
    uint256 internal INITIAL_CHAIN_ID;
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    error PermitDeadlineExpired(uint256 deadline);
    error InvalidSigner(address signer);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (deadline < block.timestamp) revert PermitDeadlineExpired(deadline);

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0) || recoveredAddress != owner)
                revert InvalidSigner(recoveredAddress);

            _approve(recoveredAddress, spender, value);
        }
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name())),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }
}