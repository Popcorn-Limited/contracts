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

struct Allocation {
    uint256 index;
    uint256 amount;
}

/**
 * @title   MultiStrategyVault
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * A simple ERC4626-Implementation of a MultiStrategyVault.
 * The vault delegates any actual protocol interaction to a selection of strategies.
 * It allows for multiple type of fees which are taken by issuing new vault shares.
 * Strategies and fees can be changed by the owner after a ragequit time.
 */
contract MultiStrategyVault is ERC4626Upgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, OwnedUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    uint256 public quitPeriod;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error InvalidAsset();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     * @param strategies_ strategies to be used to earn interest for this vault.
     * @param defaultDepositIndex_ index of the strategy that the vault should use on deposit
     * @param withdrawalQueue_ indices determining the order in which we should withdraw funds from strategies
     * @param depositLimit_ Maximum amount of assets which can be deposited.
     * @param owner_ Owner of the contract. Controls management functions.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     */
    function initialize(
        IERC20 asset_,
        IERC4626[] calldata strategies_,
        uint256 defaultDepositIndex_,
        uint256[] calldata withdrawalQueue_,
        uint256 depositLimit_,
        address owner_
    ) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Owned_init(owner_);

        if (address(asset_) == address(0)) revert InvalidAsset();

        // Set Strategies
        uint256 len = strategies_.length;
        for (uint256 i; i < len; i++) {
            if (strategies_[i].asset() != address(asset_)) {
                revert VaultAssetMismatchNewAdapterAsset();
            }
            strategies.push(strategies_[i]);
            asset_.approve(address(strategies_[i]), type(uint256).max);
        }

        // Set DefaultDepositIndex
        if (defaultDepositIndex_ > strategies.length - 1 && defaultDepositIndex_ != type(uint256).max) {
            revert InvalidIndex();
        }

        defaultDepositIndex = defaultDepositIndex_;

        // Set WithdrawalQueue
        if (withdrawalQueue_.length != strategies.length) {
            revert InvalidWithdrawalQueue();
        }

        withdrawalQueue = new uint256[](withdrawalQueue_.length);

        for (uint256 i = 0; i < withdrawalQueue_.length; i++) {
            uint256 index = withdrawalQueue_[i];

            if (index > strategies.length - 1 && index != type(uint256).max) {
                revert InvalidIndex();
            }

            withdrawalQueue[i] = index;
        }

        // Set other state variables
        quitPeriod = 3 days;
        depositLimit = depositLimit_;
        highWaterMark = convertToAssets(1e18);

        _name = string.concat("VaultCraft ", IERC20Metadata(address(asset_)).name(), " Vault");
        _symbol = string.concat("vc-", IERC20Metadata(address(asset_)).symbol());

        contractName = keccak256(abi.encodePacked("VaultCraft ", name(), block.timestamp, "Vault"));

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        emit VaultInitialized(contractName, address(asset_));
    }

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
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
        takeFees
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

        // deposit into default index strategy or leave funds idle
        if (defaultDepositIndex != type(uint256).max) {
            strategies[defaultDepositIndex].deposit(assets, address(this));
        }

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
        takeFees
    {
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

        _withdrawStrategyFunds(assets, receiver);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _withdrawStrategyFunds(uint256 amount, address receiver) internal {
        // caching
        IERC20 asset_ = IERC20(asset());
        uint256[] memory withdrawalQueue_ = withdrawalQueue;

        // Get the Vault's floating balance.
        uint256 float = asset_.balanceOf(address(this));

        if (amount > float) {
            // Iterate the withdrawal queue and get indexes
            // Will revert due to underflow if we empty the stack before pulling the desired amount.
            uint256 len = withdrawalQueue_.length;
            for (uint256 i = 0; i < len; i++) {
                uint256 missing = amount - float;

                IERC4626 strategy = strategies[withdrawalQueue_[i]];

                uint256 withdrawableAssets = strategy.previewRedeem(strategy.balanceOf(address(this)));

                if (withdrawableAssets >= missing) {
                    strategy.withdraw(missing, address(this), address(this));
                    break;
                } else if (withdrawableAssets > 0) {
                    try strategy.withdraw(withdrawableAssets, address(this), address(this)) {
                        float += withdrawableAssets;
                    } catch {}
                }
            }
        }

        asset_.safeTransfer(receiver, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        uint256 assets = IERC20(asset()).balanceOf(address(this));

        for (uint8 i; i < strategies.length; i++) {
            assets += strategies[i].convertToAssets(strategies[i].balanceOf(address(this)));
        }
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address. Delegates to adapter.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return (paused() || assets >= depositLimit_) ? 0 : convertToShares(depositLimit_ - assets);
    }

    /*//////////////////////////////////////////////////////////////
                          STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    IERC4626[] public strategies;
    IERC4626[] public proposedStrategies;
    uint256 public proposedStrategyTime;
    uint256 public defaultDepositIndex; // index of the strategy to deposit funds by default - if uint.max, leave funds idle
    uint256[] public withdrawalQueue; // indexes of the strategy order in the withdrawal queue

    event NewStrategiesProposed();
    event ChangedStrategies();

    error VaultAssetMismatchNewAdapterAsset();
    error InvalidIndex();
    error InvalidWithdrawalQueue();
    error NotPassedQuitPeriod(uint256 quitPeriod_);

    function getStrategies() external view returns (IERC4626[] memory) {
        return strategies;
    }

    function getProposedStrategies() external view returns (IERC4626[] memory) {
        return proposedStrategies;
    }

    function setDefaultDepositIndex(uint256 index) external onlyOwner {
        if (index > strategies.length - 1 && index != type(uint256).max) {
            revert InvalidIndex();
        }

        defaultDepositIndex = index;
    }

    function setWithdrawalQueue(uint256[] memory indexes) external onlyOwner {
        if (indexes.length != strategies.length) {
            revert InvalidWithdrawalQueue();
        }

        withdrawalQueue = new uint256[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            uint256 index = indexes[i];

            if (index > strategies.length - 1 && index != type(uint256).max) {
                revert InvalidIndex();
            }

            withdrawalQueue[i] = index;
        }
    }

    /**
     * @notice Propose a new adapter for this vault. Caller must be Owner.
     * @param strategies_ A new ERC4626 that should be used as a yield adapter for this asset.
     */
    function proposeStrategies(IERC4626[] calldata strategies_) external onlyOwner {
        address asset_ = asset();
        uint256 len = strategies_.length;
        for (uint256 i; i < len; i++) {
            if (strategies_[i].asset() != asset_) {
                revert VaultAssetMismatchNewAdapterAsset();
            }
            proposedStrategies.push(strategies_[i]);
        }

        proposedStrategyTime = block.timestamp;
        emit NewStrategiesProposed();
    }

    /**
     * @notice Set a new Adapter for this Vault after the quit period has passed.
     * @dev This migration function will remove all assets from the old Vault and move them into the new vault
     * @dev Additionally it will zero old allowances and set new ones
     * @dev Last we update HWM and assetsCheckpoint for fees to make sure they adjust to the new adapter
     */
    function changeStrategies() external {
        if (proposedStrategyTime == 0 || block.timestamp < proposedStrategyTime + quitPeriod) {
            revert NotPassedQuitPeriod(quitPeriod);
        }

        address asset_ = asset();
        uint256 len = strategies.length;
        for (uint256 i; i < len; i++) {
            strategies[i].redeem(strategies[i].balanceOf(address(this)), address(this), address(this));
            IERC20(asset_).approve(address(strategies[i]), 0);
        }

        delete strategies;

        len = proposedStrategies.length;
        for (uint256 i; i < len; i++) {
            strategies.push(proposedStrategies[i]);

            IERC20(asset_).approve(address(proposedStrategies[i]), type(uint256).max);
        }

        delete proposedStrategyTime;
        delete proposedStrategies;

        emit ChangedStrategies();
    }

    function pushFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            strategies[allocations[i].index].deposit(allocations[i].amount, address(this));
        }
    }

    function pullFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            if (allocations[i].amount > 0) {
                strategies[allocations[i].index].withdraw(allocations[i].amount, address(this), address(this));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;
    uint256 public highWaterMark;

    address public constant FEE_RECIPIENT = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

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

        return performanceFee_ > 0 && shareValue > highWaterMark_
            ? performanceFee_.mulDiv((shareValue - highWaterMark_) * totalSupply(), 1e36, Math.Rounding.Ceil)
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
                          DEPOSIT LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public depositLimit;

    event DepositLimitSet(uint256 depositLimit);

    /**
     * @notice Sets a limit for deposits in assets. Caller must be Owner.
     * @param _depositLimit Maximum amount of assets that can be deposited.
     */
    function setDepositLimit(uint256 _depositLimit) external onlyOwner {
        depositLimit = _depositLimit;

        emit DepositLimitSet(_depositLimit);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause deposits. Caller must be Owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause deposits. Caller must be Owner.
    function unpause() external onlyOwner {
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

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
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
