// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";
import {VaultFees, IERC4626, IERC20} from "../interfaces/vault/IVault.sol";

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

    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    uint8 internal _decimals;
    uint8 public constant decimalOffset = 9;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error InvalidAsset();
    error InvalidAdapter();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     * @param strategies_ strategies to be used to earn interest for this vault.
     * @param fees_ Desired fees in 1e18. (1e18 = 100%, 1e14 = 1 BPS)
     * @param feeRecipient_ Recipient of all vault fees. (Must not be zero address)
     * @param depositLimit_ Maximum amount of assets which can be deposited.
     * @param owner Owner of the contract. Controls management functions.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     */
    function initialize(
        IERC20 asset_,
        IERC4626[] calldata strategies_,
        VaultFees calldata fees_,
        address feeRecipient_,
        uint256 depositLimit_,
        address owner
    ) external initializer {
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Owned_init(owner);

        if (address(asset_) == address(0)) revert InvalidAsset();

        uint256 len = strategies_.length;
        for (uint256 i; i < len; i++) {
            if (strategies_[i].asset() != address(asset_))
                revert VaultAssetMismatchNewAdapterAsset();
            strategies.push(strategies_[i]);
            asset_.approve(address(strategies_[i]), type(uint256).max);
        }

        if (
            fees_.deposit >= 1e18 ||
            fees_.withdrawal >= 1e18 ||
            fees_.management >= 1e18 ||
            fees_.performance >= 1e18
        ) revert InvalidVaultFees();
        fees = fees_;

        if (feeRecipient_ == address(0)) revert InvalidFeeRecipient();
        feeRecipient = feeRecipient_;

        highWaterMark = 1e9;
        quitPeriod = 3 days;
        depositLimit = depositLimit_;

        name = string.concat(
            "VaultCraft ",
            IERC20Metadata(address(asset_)).name(),
            " Vault"
        );
        _symbol = string.concat(
            "vc-",
            IERC20Metadata(address(asset_)).symbol()
        );

        contractName = keccak256(
            abi.encodePacked("VaultCraft ", name(), block.timestamp, "Vault")
        );

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        emit VaultInitialized(contractName, address(asset_));
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

    function decimals() public view override returns (uint8) {
        return _decimals;
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

    /**
     * @notice Deposit exactly `assets` amount of tokens, issuing vault shares to `receiver`.
     * @param assets Quantity of tokens to deposit.
     * @param receiver Receiver of issued vault shares.
     * @return shares Quantity of vault shares issued to `receiver`.
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets > maxDeposit(receiver)) revert MaxError(assets);

        // Inititalize account for managementFee on first deposit
        if (totalSupply() == 0) feesUpdatedAt = block.timestamp;

        uint256 feeShares = _convertToShares(
            assets.mulDiv(uint256(fees.deposit), 1e18, Math.Rounding.Floor),
            Math.Rounding.Floor
        );

        shares = _convertToShares(assets, Math.Rounding.Floor) - feeShares;
        if (shares == 0) revert ZeroAmount();

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _mint(receiver, shares);

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // deposit into default index strategy or leave funds idle
        if (defaultDepositIndex != type(uint256).max) {
            strategies[defaultDepositIndex].deposit(assets, address(this));
        }

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    /**
     * @notice Mint exactly `shares` vault shares to `receiver`, taking the necessary amount of `asset` from the caller.
     * @param shares Quantity of shares to mint.
     * @param receiver Receiver of issued vault shares.
     * @return assets Quantity of assets deposited by caller.
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256 assets) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (shares == 0) revert ZeroAmount();

        // Inititalize account for managementFee on first deposit
        if (totalSupply() == 0) feesUpdatedAt = block.timestamp;

        uint256 depositFee = uint256(fees.deposit);

        uint256 feeShares = shares.mulDiv(
            depositFee,
            1e18 - depositFee,
            Math.Rounding.Floor
        );

        assets = _convertToAssets(shares + feeShares, Math.Rounding.Ceil);

        if (assets > maxMint(receiver)) revert MaxError(assets);

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _mint(receiver, shares);

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // deposit into default index strategy or leave funds idle
        if (defaultDepositIndex != type(uint256).max) {
            strategies[defaultDepositIndex].deposit(assets, address(this));
        }

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets) public returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    /**
     * @notice Burn shares from `owner` in exchange for `assets` amount of underlying token.
     * @param assets Quantity of underlying `asset` token to withdraw.
     * @param receiver Receiver of underlying token.
     * @param owner Owner of burned vault shares.
     * @return shares Quantity of vault shares burned in exchange for `assets`.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets > maxWithdraw(owner)) revert MaxError(assets);

        shares = _convertToShares(assets, Math.Rounding.Ceil);
        if (shares == 0) revert ZeroAmount();

        uint256 withdrawalFee = uint256(fees.withdrawal);

        uint256 feeShares = shares.mulDiv(
            withdrawalFee,
            1e18 - withdrawalFee,
            Math.Rounding.Floor
        );

        shares += feeShares;

        if (msg.sender != owner)
            _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

        _burn(owner, shares);

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _withdrawStrategyFunds(assets, receiver);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /**
     * @notice Burn exactly `shares` vault shares from `owner` and send underlying `asset` tokens to `receiver`.
     * @param shares Quantity of vault shares to exchange for underlying tokens.
     * @param receiver Receiver of underlying tokens.
     * @param owner Owner of burned vault shares.
     * @return assets Quantity of `asset` sent to `receiver`.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (shares == 0) revert ZeroAmount();
        if (shares > maxRedeem(owner)) revert MaxError(shares);

        if (msg.sender != owner)
            _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

        uint256 feeShares = shares.mulDiv(
            uint256(fees.withdrawal),
            1e18,
            Math.Rounding.Floor
        );

        assets = _convertToAssets(shares - feeShares, Math.Rounding.Floor);

        _burn(owner, shares);

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _withdrawStrategyFunds(assets, receiver);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _withdrawStrategyFunds(uint256 amount, address receiver) internal {
        // caching
        IERC20 asset_ = IERC20(asset());
        uint256[] memory withdrawalQueue_ = withdrawalQueue;

        // Get the Vault's floating balance.
        uint256 float = asset_.balanceOf(address(this));

        if (amount < float) {
            asset_.safeTransfer(receiver, amount);
        } else {
            // If the amount is greater than the float, withdraw from strategies.
            if (float > 0) {
                asset_.safeTransfer(receiver, float);
            }

            // Iterate the withdrawal queue and get indexes
            // Will revert due to underflow if we empty the stack before pulling the desired amount.
            uint256 len = withdrawalQueue_.length;
            for (uint256 i = 0; i < len; i++) {
                uint256 missing = amount - float;

                IERC4626 strategy = strategies[withdrawalQueue_[i]];

                uint256 withdrawableAssets = strategy.previewRedeem(
                    strategy.balanceOf(address(this))
                );

                if (withdrawableAssets >= missing) {
                    strategy.withdraw(missing, receiver, address(this));
                    break;
                } else if (withdrawableAssets > 0) {
                    strategy.withdraw(
                        withdrawableAssets,
                        receiver,
                        address(this)
                    );
                    float += withdrawableAssets;
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev TODO - should we only track deposits / withdrawals and update balances on harvest operations to reduce gas costs?
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

    /**
     * @notice Simulate the effects of a deposit at the current block, given current on-chain conditions.
     * @param assets Exact amount of underlying `asset` token to deposit
     * @return shares of the vault issued in exchange to the user for `assets`
     * @dev This method accounts for issuance of accrued fee shares.
     */
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256 shares) {
        assets -= assets.mulDiv(
            uint256(fees.deposit),
            1e18,
            Math.Rounding.Floor
        );
        shares = _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @notice Simulate the effects of a mint at the current block, given current on-chain conditions.
     * @param shares Exact amount of vault shares to mint.
     * @return assets quantity of underlying needed in exchange to mint `shares`.
     * @dev This method accounts for issuance of accrued fee shares.
     */
    function previewMint(
        uint256 shares
    ) public view override returns (uint256 assets) {
        uint256 depositFee = uint256(fees.deposit);
        shares += shares.mulDiv(
            depositFee,
            1e18 - depositFee,
            Math.Rounding.Floor
        );
        assets = _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /**
     * @notice Simulate the effects of a withdrawal at the current block, given current on-chain conditions.
     * @param assets Exact amount of `assets` to withdraw
     * @return shares to be burned in exchange for `assets`
     * @dev This method accounts for both issuance of fee shares and withdrawal fee.
     */
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256 shares) {
        shares = _convertToShares(assets, Math.Rounding.Ceil);

        uint256 withdrawalFee = uint256(fees.withdrawal);
        shares += shares.mulDiv(
            withdrawalFee,
            1e18 - withdrawalFee,
            Math.Rounding.Floor
        );
    }

    /**
     * @notice Simulate the effects of a redemption at the current block, given current on-chain conditions.
     * @param shares Exact amount of `shares` to redeem
     * @return assets quantity of underlying returned in exchange for `shares`.
     * @dev This method accounts for both issuance of fee shares and withdrawal fee.
     */
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256 assets) {
        uint256 feeShares = shares.mulDiv(
            uint256(fees.withdrawal),
            1e18,
            Math.Rounding.Floor
        );

        assets = _convertToAssets(shares - feeShares, Math.Rounding.Floor);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address. Delegates to adapter.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return
            (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return
            (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /*//////////////////////////////////////////////////////////////
                        FEE ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Management fee that has accrued since last fee harvest.
     * @return Accrued management fee in underlying `asset` token.
     * @dev Management fee is annualized per minute, based on 525,600 minutes per year. Total assets are calculated using
     *  the average of their current value and the value at the previous fee harvest checkpoint. This method is similar to
     *  calculating a definite integral using the trapezoid rule.
     */
    function accruedManagementFee() public view returns (uint256) {
        uint256 managementFee = fees.management;
        return
            managementFee > 0
                ? managementFee.mulDiv(
                    totalAssets() * (block.timestamp - feesUpdatedAt),
                    SECONDS_PER_YEAR,
                    Math.Rounding.Floor
                ) / 1e18
                : 0;
    }

    /**
     * @notice Performance fee that has accrued since last fee harvest.
     * @return Accrued performance fee in underlying `asset` token.
     * @dev Performance fee is based on a high water mark value. If vault share value has increased above the
     *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
     */
    function accruedPerformanceFee() public view returns (uint256) {
        uint256 highWaterMark_ = highWaterMark;
        uint256 shareValue = convertToAssets(1e18);
        uint256 performanceFee = fees.performance;

        return
            performanceFee > 0 && shareValue > highWaterMark_
                ? performanceFee.mulDiv(
                    (shareValue - highWaterMark_) * totalSupply(),
                    1e36,
                    Math.Rounding.Floor
                )
                : 0;
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public highWaterMark;
    uint256 public assetsCheckpoint;
    uint256 public feesUpdatedAt;

    error InsufficientWithdrawalAmount(uint256 amount);

    /// @notice Minimal function to call `takeFees` modifier.
    function takeManagementAndPerformanceFees()
        external
        nonReentrant
        takeFees
    {}

    /// @notice Collect management and performance fees and update vault share high water mark.
    modifier takeFees() {
        uint256 totalFee = accruedManagementFee() + accruedPerformanceFee();
        uint256 currentAssets = totalAssets();
        uint256 shareValue = convertToAssets(1e18);

        if (shareValue > highWaterMark) highWaterMark = shareValue;

        if (totalFee > 0 && currentAssets > 0) {
            uint256 supply = totalSupply();
            uint256 feeInShare = supply == 0
                ? totalFee
                : totalFee.mulDiv(
                    supply,
                    currentAssets - totalFee,
                    Math.Rounding.Floor
                );
            _mint(feeRecipient, feeInShare);
        }

        feesUpdatedAt = block.timestamp;

        _;
    }

    /*//////////////////////////////////////////////////////////////
                            FEE MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    VaultFees public fees;

    VaultFees public proposedFees;
    uint256 public proposedFeeTime;

    address public feeRecipient;

    event NewFeesProposed(VaultFees newFees, uint256 timestamp);
    event ChangedFees(VaultFees oldFees, VaultFees newFees);
    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);

    error InvalidVaultFees();
    error InvalidFeeRecipient();
    error NotPassedQuitPeriod(uint256 quitPeriod);

    /**
     * @notice Propose new fees for this vault. Caller must be owner.
     * @param newFees Fees for depositing, withdrawal, management and performance in 1e18.
     * @dev Fees can be 0 but never 1e18 (1e18 = 100%, 1e14 = 1 BPS)
     */
    function proposeFees(VaultFees calldata newFees) external onlyOwner {
        if (
            newFees.deposit >= 1e18 ||
            newFees.withdrawal >= 1e18 ||
            newFees.management >= 1e18 ||
            newFees.performance >= 1e18
        ) revert InvalidVaultFees();

        proposedFees = newFees;
        proposedFeeTime = block.timestamp;

        emit NewFeesProposed(newFees, block.timestamp);
    }

    /// @notice Change fees to the previously proposed fees after the quit period has passed.
    function changeFees() external takeFees {
        if (
            proposedFeeTime == 0 ||
            block.timestamp < proposedFeeTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);

        emit ChangedFees(fees, proposedFees);

        fees = proposedFees;
        feesUpdatedAt = block.timestamp;

        delete proposedFees;
        delete proposedFeeTime;
    }

    /**
     * @notice Change `feeRecipient`. Caller must be Owner.
     * @param _feeRecipient The new fee recipient.
     * @dev Accrued fees wont be transferred to the new feeRecipient.
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);

        feeRecipient = _feeRecipient;
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

    function getStrategies() external view returns (IERC4626[] memory) {
        return strategies;
    }

    function getProposedStrategies() external view returns (IERC4626[] memory) {
        return proposedStrategies;
    }

    function setDefaultDepositIndex(uint256 index) external onlyOwner {
        if (index > strategies.length - 1 && index != type(uint256).max)
            revert InvalidIndex();

        defaultDepositIndex = index;
    }

    function setWithdrawalQueue(uint256[] memory indexes) external onlyOwner {
        if (indexes.length != strategies.length)
            revert InvalidWithdrawalQueue();

        withdrawalQueue = new uint256[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            uint256 index = indexes[i];

            if (index > strategies.length - 1 && index != type(uint256).max)
                revert InvalidIndex();

            withdrawalQueue[i] = index;
        }
    }

    /**
     * @notice Propose a new adapter for this vault. Caller must be Owner.
     * @param strategies_ A new ERC4626 that should be used as a yield adapter for this asset.
     */
    function proposeStrategies(
        IERC4626[] calldata strategies_
    ) external onlyOwner {
        address asset_ = asset();
        uint256 len = strategies_.length;
        for (uint256 i; i < len; i++) {
            if (strategies_[i].asset() != asset_)
                revert VaultAssetMismatchNewAdapterAsset();
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
    function changeStrategies() external takeFees {
        if (
            proposedStrategyTime == 0 ||
            block.timestamp < proposedStrategyTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);

        address asset_ = asset();
        uint256 len = strategies.length;
        for (uint256 i; i < len; i++) {
            strategies[i].redeem(
                strategies[i].balanceOf(address(this)),
                address(this),
                address(this)
            );
            IERC20(asset_).approve(address(strategies[i]), 0);
        }

        delete strategies;

        len = proposedStrategies.length;
        for (uint256 i; i < len; i++) {
            strategies.push(proposedStrategies[i]);

            IERC20(asset_).approve(
                address(proposedStrategies[i]),
                type(uint256).max
            );
        }

        delete proposedStrategyTime;
        delete proposedStrategies;

        emit ChangedStrategies();
    }

    function pushFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            strategies[allocations[i].index].deposit(
                allocations[i].amount,
                address(this)
            );
        }
    }

    function pullFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            if (allocations[i].amount > 0)
                strategies[allocations[i].index].withdraw(
                    allocations[i].amount,
                    address(this),
                    address(this)
                );
        }
    }

    /*//////////////////////////////////////////////////////////////
                          RAGE QUIT LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public quitPeriod;

    event QuitPeriodSet(uint256 quitPeriod);

    error InvalidQuitPeriod();

    /**
     * @notice Set a quitPeriod for rage quitting after new adapter or fees are proposed. Caller must be Owner.
     * @param _quitPeriod Time to rage quit after proposal.
     */
    function setQuitPeriod(uint256 _quitPeriod) external onlyOwner {
        if (
            block.timestamp < proposedStrategyTime + quitPeriod ||
            block.timestamp < proposedFeeTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);
        if (_quitPeriod < 1 days || _quitPeriod > 7 days)
            revert InvalidQuitPeriod();

        quitPeriod = _quitPeriod;

        emit QuitPeriodSet(quitPeriod);
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

            if (recoveredAddress == address(0) || recoveredAddress != owner)
                revert InvalidSigner(recoveredAddress);

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
