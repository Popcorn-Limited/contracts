// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {
    ERC4626Upgradeable,
    IERC20Metadata,
    ERC20Upgradeable as ERC20,
    IERC4626,
    IERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";

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
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     */
    function __BaseStrategy_init(address asset_, address owner_, bool autoDeposit_) internal onlyInitializing {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Owned_init(owner_);
        __ERC4626_init(IERC20Metadata(asset_));

        autoDeposit = autoDeposit_;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();

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
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (shares == 0 || assets == 0) revert ZeroAmount();

        // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

        if (autoDeposit) _protocolDeposit(assets, shares, bytes(""));

        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (shares == 0 || assets == 0) revert ZeroAmount();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // We call this before the `burn` to allow for normal calculations with shares before they get burned
        // Since we transfer assets after the burn the function should remain safe
        if (!paused()) {
            uint256 float = IERC20(asset()).balanceOf(address(this));
            if (assets > float) {
                uint256 missing = assets - float;
                _protocolWithdraw(missing, convertToShares(missing), bytes(""));
            }
        }

        // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        IERC20(asset()).safeTransfer(receiver, assets);

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
        return IERC20(asset()).balanceOf(address(this)) + _totalAssets();
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
    function convertToUnderlyingShares(uint256 assets, uint256 shares) public view virtual returns (uint256) {}

    function rewardTokens() external view virtual returns (address[] memory) {}

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function maxDeposit(address) public view virtual override returns (uint256) {
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
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit into the underlying protocol.
    function _protocolDeposit(uint256 assets, uint256 shares, bytes memory data) internal virtual {
        // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
    }

    /// @notice Withdraw from the underlying protocol.
    function _protocolWithdraw(uint256 assets, uint256 shares, bytes memory data) internal virtual {
        // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    bool public autoDeposit;
    address public keeper;

    event AutoDepositToggled(bool oldState, bool newState);
    event Harvested();
    event KeeperChanged(address prev, address curr);

    error NotKeeperNorOwner();

    function claim() internal virtual returns (bool success) {
        // try auraRewards.getReward() {
        //     success = true;
        // } catch {}
    }

    function harvest(bytes memory data) external virtual onlyKeeperOrOwner {}

    function pushFunds(uint256 assets, bytes memory data) external virtual onlyKeeperOrOwner {
        _protocolDeposit(assets, convertToShares(assets), data);
    }

    function pullFunds(uint256 assets, bytes memory data) external virtual onlyKeeperOrOwner {
        _protocolWithdraw(assets, convertToShares(assets), data);
    }

    function toggleAutoDeposit() external onlyOwner {
        emit AutoDepositToggled(autoDeposit, !autoDeposit);
        autoDeposit = !autoDeposit;
    }

    function setKeeper(address keeper_) external onlyOwner {
        emit KeeperChanged(keeper, keeper_);
        keeper = keeper_;
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && msg.sender != keeper) {
            revert NotKeeperNorOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                      PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause Deposits and withdraw all funds from the underlying protocol. Caller must be owner.
    function pause() external virtual onlyOwner {
        _pause();
    }

    /// @notice Unpause Deposits and deposit all funds into the underlying protocol. Caller must be owner.
    function unpause() external virtual onlyOwner {
        _unpause();
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

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
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

            if (recoveredAddress == address(0) || recoveredAddress != owner) {
                revert InvalidSigner(recoveredAddress);
            }

            _approve(recoveredAddress, spender, value);
        }
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
