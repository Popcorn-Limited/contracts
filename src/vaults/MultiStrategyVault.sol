// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20, IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";

/**
 * @param asset_ Underlying Asset which users will deposit.
 * @param strategies_ strategies to be used to earn interest for this vault.
 * @param depositIndex_ index of the strategy that the vault should use on deposit
 * @param withdrawalQueue_ indices determining the order in which we should withdraw funds from strategies
 * @param depositLimit_ Maximum amount of assets which can be deposited.
 * @param owner_ Owner of the contract. Controls management functions.
 * @param feeRecipient_ Address that will receive fees.
 */
struct InitializeParams {
    IERC20 asset;
    IERC4626[] strategies;
    uint256 depositIndex;
    uint256[] withdrawalQueue;
    uint256 depositLimit;
    address owner;
    address feeRecipient;
}

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
contract MultiStrategyVault is
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnedUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    uint256 public quitPeriod;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error InvalidAsset();
    error Duplicate();

    // constructor() {
    //     _disableInitializers();
    // }

    /**
     * @notice Initialize a new Vault.
     * @param params InitializeParams struct containing all necessary parameters.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     * @dev overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
     */
    function initialize(InitializeParams memory params) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC4626_init(IERC20Metadata(address(params.asset)));
        __Owned_init(params.owner);

        if (address(params.asset) == address(0)) revert InvalidAsset();

        // Cache
        uint256 len = params.strategies.length;

        // Verify WithdrawalQueue length
        if (params.withdrawalQueue.length != len) {
            revert InvalidWithdrawalQueue();
        }

        if (len > 0) {
            // Verify strategies and withdrawal queue + approve asset for strategies
            for (uint256 i; i < len; i++) {
                _verifyStrategyAndWithdrawalQueue(
                    i,
                    len,
                    address(params.asset),
                    params.strategies,
                    params.withdrawalQueue
                );

                // Approve asset for strategy
                // Doing this inside this loop instead of its own loop for gas savings
                params.asset.approve(
                    address(params.strategies[i]),
                    type(uint256).max
                );
            }

            // Validate depositIndex
            if (
                params.depositIndex >= len &&
                params.depositIndex != type(uint256).max
            ) {
                revert InvalidIndex();
            }

            // Set withdrawalQueue and strategies
            strategies = params.strategies;
            withdrawalQueue = params.withdrawalQueue;
        } else {
            // Validate depositIndex
            if (params.depositIndex != type(uint256).max) {
                revert InvalidIndex();
            }
        }

        depositIndex = params.depositIndex;

        // Set other state variables
        quitPeriod = 1 days;
        depositLimit = params.depositLimit;
        highWaterMark = convertToAssets(1e18);
        FEE_RECIPIENT = params.feeRecipient;

        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(address(params.asset)).name(),
            " Vault"
        );
        _symbol = string.concat(
            "vc-",
            IERC20Metadata(address(params.asset)).symbol()
        );

        contractName = keccak256(
            abi.encodePacked("VaultCraft ", name(), block.timestamp, "Vault")
        );

        emit VaultInitialized(contractName, address(params.asset));
    }

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
    }

    /// Helper function to verify strategies and withdrawal queue and prevent stack-too-deep
    function _verifyStrategyAndWithdrawalQueue(
        uint256 i,
        uint256 len,
        address asset_,
        IERC4626[] memory strategies_,
        uint256[] memory withdrawalQueue_
    ) internal view {
        // Cache
        uint256 index = withdrawalQueue_[i];
        IERC4626 strategy = strategies_[i];

        // Verify asset matching
        if (strategy.asset() != asset_) {
            revert VaultAssetMismatchNewAdapterAsset();
        }

        // Verify index not out of bound
        if (index > len - 1) {
            revert InvalidIndex();
        }

        // Check for duplicates
        for (uint256 n; n < len; n++) {
            if (n != i) {
                if (
                    address(strategy) == address(strategies_[n]) ||
                    index == withdrawalQueue_[n]
                ) {
                    revert Duplicate();
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 withdrawalLeewayBps = 100;

    event StrategyWithdrawalFailed(address strategy, uint256 amount);
    event WithdrawalLeeWayUpdated(uint256 oldLeeway, uint256 newLeeway);

    error ZeroAmount();
    error Misconfigured();

    function setWithdrawalLeeway(
        uint256 _withdrawalLeewayBps
    ) external onlyOwner {
        require(_withdrawalLeewayBps <= 10_000, "Invalid withdrawal leeway");
        uint256 oldLeeway = withdrawalLeewayBps;
        withdrawalLeewayBps = _withdrawalLeewayBps;
        emit WithdrawalLeeWayUpdated(oldLeeway, _withdrawalLeewayBps);
    }

    function deposit(uint256 assets) external returns (uint256) {
        return deposit(assets, msg.sender);
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    function withdraw(uint256 assets) external returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function withdraw(
        uint256 assets,
        Allocation[] calldata allocations
    ) external returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender, allocations);
    }

    function withdraw(
        uint256 assets,
        address owner,
        address recipient,
        Allocation[] calldata allocations
    ) public returns (uint256) {
        _checkPullAllocation(assets, allocations);

        _pullFunds(allocations);

        return withdraw(assets, owner, recipient);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    function redeem(
        uint256 shares,
        Allocation[] calldata allocations
    ) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender, allocations);
    }

    function redeem(
        uint256 shares,
        address owner,
        address recipient,
        Allocation[] calldata allocations
    ) public returns (uint256) {
        uint256 assets = convertToAssets(shares);
        _checkPullAllocation(assets, allocations);

        _pullFunds(allocations);

        return redeem(shares, owner, recipient);
    }

    function _checkPullAllocation(
        uint256 assets,
        Allocation[] calldata allocations
    ) internal view {
        uint256 len = allocations.length;
        if (len > strategies.length) revert Misconfigured();

        uint256 pullAmount = IERC20(asset()).balanceOf(address(this));
        for (uint256 i; i < len; i++) {
            pullAmount += allocations[i].amount;
        }
        if ((assets + (assets * withdrawalLeewayBps) / 10_000) > pullAmount) {
            revert Misconfigured();
        }
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {
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

        // deposit into default index strategy or leave funds idle
        if (depositIndex != type(uint256).max) {
            strategies[depositIndex].deposit(assets, address(this));
        }

        _mint(receiver, shares);

        _takeFees();

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
    ) internal override nonReentrant {
        if (shares == 0 || assets == 0) revert ZeroAmount();
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _takeFees();

        // If _asset is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
        // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
        // shares are burned and after the assets are transferred, which is a valid state.
        _burn(owner, shares);

        // caching
        IERC20 asset_ = IERC20(asset());
        uint256[] memory withdrawalQueue_ = withdrawalQueue;

        // Get the Vault's floating balance.
        uint256 float = asset_.balanceOf(address(this));

        if (withdrawalQueue_.length > 0 && assets > float) {
            _withdrawStrategyFunds(assets, float, withdrawalQueue_);
        }

        asset_.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _withdrawStrategyFunds(
        uint256 amount,
        uint256 float,
        uint256[] memory queue
    ) internal {
        // Iterate the withdrawal queue and get indexes
        // Will revert due to underflow if we empty the stack before pulling the desired amount.
        uint256 len = queue.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 missing = amount - float;

            IERC4626 strategy = strategies[queue[i]];

            uint256 withdrawableAssets = strategy.previewRedeem(
                strategy.balanceOf(address(this))
            );

            if (withdrawableAssets >= missing) {
                try strategy.withdraw(missing, address(this), address(this)) {
                    break;
                } catch {
                    emit StrategyWithdrawalFailed(address(strategy), missing);
                }
            } else if (withdrawableAssets > 0) {
                try
                    strategy.withdraw(
                        withdrawableAssets,
                        address(this),
                        address(this)
                    )
                {
                    float += withdrawableAssets;
                } catch {
                    emit StrategyWithdrawalFailed(
                        address(strategy),
                        withdrawableAssets
                    );
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        uint256 assets = IERC20(asset()).balanceOf(address(this));

        for (uint8 i; i < strategies.length; i++) {
            assets += strategies[i].convertToAssets(
                strategies[i].balanceOf(address(this))
            );
        }
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return
            (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address.
    /// @dev overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        if (paused() || assets >= depositLimit_) return 0;

        if (depositLimit_ == type(uint256).max) return depositLimit_;

        return convertToShares(depositLimit_ - assets);
    }

    /*//////////////////////////////////////////////////////////////
                          STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    IERC4626[] public strategies;
    IERC4626[] public proposedStrategies;

    uint256 public proposedStrategyTime;

    uint256 public depositIndex; // index of the strategy to deposit funds by default - if uint.max, leave funds idle
    uint256 public proposedDepositIndex; // index of the strategy to deposit funds by default - if uint.max, leave funds idle

    uint256[] public withdrawalQueue; // indexes of the strategy order in the withdrawal queue
    uint256[] public proposedWithdrawalQueue;

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

    function getWithdrawalQueue() external view returns (uint256[] memory) {
        return withdrawalQueue;
    }

    function getProposedWithdrawalQueue()
        external
        view
        returns (uint256[] memory)
    {
        return proposedWithdrawalQueue;
    }

    /**
     * @notice Sets a new depositIndex. Caller must be Owner.
     * @param index The index controls which strategy will be used on user deposits.
     * @dev To simply transfer user assets into the vault without using a strategy set the index to `type(uint256).max`
     */
    function setDepositIndex(uint256 index) external onlyOwner {
        if (index > strategies.length - 1 && index != type(uint256).max) {
            revert InvalidIndex();
        }

        depositIndex = index;
    }

    /**
     * @notice Sets a new withdrawal queue. Caller must be Owner.
     * @param newQueue The order in which the vault should withdraw from the `strategies`
     * @dev Verifies that now index is out of bounds or duplicate. Each strategy index must be included exactly once.
     */
    function setWithdrawalQueue(uint256[] memory newQueue) external onlyOwner {
        uint256 len = newQueue.length;
        if (len != strategies.length) {
            revert InvalidWithdrawalQueue();
        }

        for (uint256 i; i < len; i++) {
            uint256 index = newQueue[i];

            // Verify index not out of bound
            if (index > len - 1) {
                revert InvalidIndex();
            }

            // Check for duplicates
            for (uint256 n; n < len; n++) {
                if (n != i) {
                    if (index == newQueue[n]) {
                        revert Duplicate();
                    }
                }
            }
        }

        withdrawalQueue = newQueue;
    }

    /**
     * @notice Propose new strategies for this vault. Caller must be Owner.
     * @param strategies_ New ERC4626s that should be used as a strategy for this asset.
     * @param withdrawalQueue_ The order in which the vault should withdraw from the `strategies`
     * @param depositIndex_ Index of the strategy to be used on user deposits
     */
    function proposeStrategies(
        IERC4626[] calldata strategies_,
        uint256[] calldata withdrawalQueue_,
        uint256 depositIndex_
    ) external onlyOwner {
        // Cache
        address asset_ = asset();
        uint256 len = strategies_.length;

        // Verify WithdrawalQueue length
        if (withdrawalQueue_.length != len) {
            revert InvalidWithdrawalQueue();
        }

        if (len > 0) {
            // Validate depositIndex
            if (depositIndex_ >= len && depositIndex_ != type(uint256).max) {
                revert InvalidIndex();
            }

            // Verify strategies and withdrawal queue
            for (uint256 i; i < len; i++) {
                _verifyStrategyAndWithdrawalQueue(
                    i,
                    len,
                    asset_,
                    strategies_,
                    withdrawalQueue_
                );
            }
        } else {
            // Validate depositIndex
            if (depositIndex_ != type(uint256).max) {
                revert InvalidIndex();
            }
        }

        // Set proposed state
        proposedStrategies = strategies_;
        proposedWithdrawalQueue = withdrawalQueue_;
        proposedDepositIndex = depositIndex_;
        proposedStrategyTime = block.timestamp;

        emit NewStrategiesProposed();
    }

    /**
     * @notice Set new strategies for this Vault after the quit period has passed.
     * @dev This migration function will remove all assets from the old strategies and move them into the new strategies
     * @dev Additionally it will zero old allowances and set new ones
     */
    function changeStrategies() external {
        if (
            proposedStrategyTime == 0 ||
            block.timestamp < proposedStrategyTime + quitPeriod
        ) {
            revert NotPassedQuitPeriod(quitPeriod);
        }

        address asset_ = asset();
        uint256 len = strategies.length;
        if (len > 0) {
            for (uint256 i; i < len; i++) {
                uint256 stratBal = strategies[i].balanceOf(address(this));
                if (stratBal > 0) {
                    strategies[i].redeem(
                        stratBal,
                        address(this),
                        address(this)
                    );
                }
                IERC20(asset_).approve(address(strategies[i]), 0);
            }
        }

        len = proposedStrategies.length;
        if (len > 0) {
            for (uint256 i; i < len; i++) {
                IERC20(asset_).approve(
                    address(proposedStrategies[i]),
                    type(uint256).max
                );
            }
        }

        strategies = proposedStrategies;
        withdrawalQueue = proposedWithdrawalQueue;
        depositIndex = proposedDepositIndex;

        delete proposedStrategies;
        delete proposedWithdrawalQueue;
        delete proposedDepositIndex;
        delete proposedStrategyTime;

        emit ChangedStrategies();
    }

    /**
     * @notice Push idle funds into strategies. Caller must be Owner.
     * @param allocations An array of structs each including the strategyIndex to deposit into and the amount of assets
     */
    function pushFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            strategies[allocations[i].index].deposit(
                allocations[i].amount,
                address(this)
            );
        }
    }

    /**
     * @notice Pull funds out of strategies to be reallocated into different strategies. Caller must be Owner.
     * @param allocations An array of structs each including the strategyIndex to withdraw from and the amount of assets
     */
    function pullFunds(Allocation[] calldata allocations) external onlyOwner {
        _pullFunds(allocations);
    }

    function _pullFunds(Allocation[] calldata allocations) internal {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            if (allocations[i].amount > 0) {
                strategies[allocations[i].index].withdraw(
                    allocations[i].amount,
                    address(this),
                    address(this)
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;
    uint256 public highWaterMark;

    uint256 public managementFee;
    uint256 public feesUpdatedAt;

    address public FEE_RECIPIENT;

    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    event FeesChanged(
        uint256 oldPerformanceFee,
        uint256 newPerformanceFee,
        uint256 oldManagementFee,
        uint256 newManagementFee
    );

    error InvalidFee(uint256 fee);

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
                    Math.Rounding.Ceil
                )
                : 0;
    }

    /**
     * @notice Management fee that has accrued since last fee harvest.
     * @return Accrued management fee in underlying `asset` token.
     * @dev Management fee is annualized per minute, based on 525,600 minutes per year. Total assets are calculated using
     *  the average of their current value and the value at the previous fee harvest checkpoint. This method is similar to
     *  calculating a definite integral using the trapezoid rule.
     */
    function accruedManagementFee() public view returns (uint256) {
        uint256 managementFee_ = managementFee;

        return
            managementFee_ > 0
                ? managementFee_.mulDiv(
                    totalAssets() * (block.timestamp - feesUpdatedAt),
                    SECONDS_PER_YEAR,
                    Math.Rounding.Floor
                ) / 1e18
                : 0;
    }

    /**
     * @notice Set a new performance fee for this adapter. Caller must be owner.
     * @param performanceFee_ performance fee in 1e18.
     * @param managementFee_ management fee in 1e18.
     * @dev Performance fee can be 0 but never more than 2e17 (1e18 = 100%, 1e14 = 1 BPS)
     * @dev Management fee can be 0 but never more than 1e17 (1e18 = 100%, 1e14 = 1 BPS)
     */
    function setFees(
        uint256 performanceFee_,
        uint256 managementFee_
    ) public onlyOwner {
        // Dont take more than 20% performanceFee
        if (performanceFee_ > 2e17) revert InvalidFee(performanceFee_);
        // Dont take more than 10% managementFee
        if (managementFee_ > 1e17) revert InvalidFee(managementFee_);

        _takeFees();

        emit FeesChanged(
            performanceFee,
            performanceFee_,
            managementFee,
            managementFee_
        );

        performanceFee = performanceFee_;
        managementFee = managementFee_;
    }

    function takeFees() external {
        _takeFees();
    }

    function _takeFees() internal {
        uint256 fee = accruedPerformanceFee() + accruedManagementFee();
        uint256 shareValue = convertToAssets(1e18);

        if (shareValue > highWaterMark) highWaterMark = shareValue;

        if (fee > 0) _mint(FEE_RECIPIENT, convertToShares(fee));

        feesUpdatedAt = block.timestamp;
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

            if (recoveredAddress == address(0) || recoveredAddress != owner) {
                revert InvalidSigner(recoveredAddress);
            }

            _approve(recoveredAddress, spender, value);
        }
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
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
