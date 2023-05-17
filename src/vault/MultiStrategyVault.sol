// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable, IERC20MetadataUpgradeable as IERC20Metadata, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";
import {VaultFees, IERC4626, IERC20} from "../interfaces/vault/IVault.sol";
import "forge-std/console.sol";

struct AdapterConfig {
    IERC4626 adapter;
    uint64 allocation;
}

/**
 * @title   Vault
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * A simple ERC4626-Implementation of a Vault.
 * The vault delegates any actual protocol interaction to an adapter.
 * It allows for multiple type of fees which are taken by issuing new vault shares.
 * Adapter and fees can be changed by the owner after a ragequit time.
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

    mapping(address => uint256) public _leftOver;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error InvalidAsset();
    error InvalidAdapter();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     * @param adapters_ Adapter which will be used to interact with the wrapped protocol.
     * @param adapterCount_ Amount of adapters to use.
     * @param fees_ Desired fees in 1e18. (1e18 = 100%, 1e14 = 1 BPS)
     * @param feeRecipient_ Recipient of all vault fees. (Must not be zero address)
     * @param depositLimit_ Maximum amount of assets which can be deposited.
     * @param owner Owner of the contract. Controls management functions.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     */
    function initialize(
        IERC20 asset_,
        AdapterConfig[10] calldata adapters_,
        uint8 adapterCount_,
        VaultFees calldata fees_,
        address feeRecipient_,
        uint256 depositLimit_,
        address owner
    ) external initializer {
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Owned_init(owner);

        if (address(asset_) == address(0)) revert InvalidAsset();
        _verifyAdapterConfig(adapters_, adapterCount_);

        adapterCount = adapterCount_;
        for (uint8 i; i < adapterCount_; i++) {
            adapters[i] = adapters_[i];

            asset_.approve(address(adapters_[i].adapter), type(uint256).max);
        }

        _decimals = IERC20Metadata(address(asset_)).decimals() + decimalOffset; // Asset decimals + decimal offset to combat inflation attacks

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        if (
            fees_.deposit >= 1e18 ||
            fees_.withdrawal >= 1e18 ||
            fees_.management >= 1e18 ||
            fees_.performance >= 1e18
        ) revert InvalidVaultFees();
        fees = fees_;

        if (feeRecipient_ == address(0)) revert InvalidFeeRecipient();
        feeRecipient = feeRecipient_;

        contractName = keccak256(
            abi.encodePacked("Popcorn", name(), block.timestamp, "Vault")
        );

        feesUpdatedAt = block.timestamp;
        highWaterMark = 1e9;
        quitPeriod = 3 days;
        depositLimit = depositLimit_;

        emit VaultInitialized(contractName, address(asset_));

        _name = string.concat(
            "Popcorn ",
            IERC20Metadata(address(asset_)).name(),
            " Vault"
        );
        _symbol = string.concat(
            "pop-",
            IERC20Metadata(address(asset_)).symbol()
        );
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

    function decimals()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (uint8)
    {
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

    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets > maxDeposit(receiver)) revert MaxError(assets);

        uint256 feeShares = _convertToShares(
            assets.mulDiv(uint256(fees.deposit), 1e18, Math.Rounding.Down),
            Math.Rounding.Down
        );

        shares = _convertToShares(assets, Math.Rounding.Down) - feeShares;

        if (shares == 0) revert ZeroAmount();

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256 assets) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (shares == 0) revert ZeroAmount();
        if (shares > maxMint(receiver)) revert MaxError(shares);

        uint256 depositFee = uint256(fees.deposit);

        uint256 feeShares = shares.mulDiv(
            depositFee,
            1e18 - depositFee,
            Math.Rounding.Down
        );

        assets = _convertToAssets(shares + feeShares, Math.Rounding.Up);

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (receiver == address(0)) revert InvalidReceiver();

        IERC20(asset()).safeTransferFrom(caller, address(this), assets);

        uint256 spentAssets;
        uint256 usedAssets;
        uint256 revisedAssets = assets + _leftOver[receiver];
        for (uint8 i; i < adapterCount; i++) {
            usedAssets = revisedAssets.mulDiv(
                adapters[i].allocation,
                1e18,
                Math.Rounding.Down
            );
            adapters[i].adapter.deposit(usedAssets, address(this));
            spentAssets += usedAssets;
        }

        _leftOver[receiver] = revisedAssets - spentAssets;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
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

        shares = _convertToShares(assets, Math.Rounding.Up);
        if (shares == 0) revert ZeroAmount();

        uint256 withdrawalFee = uint256(fees.withdrawal);

        uint256 feeShares = shares.mulDiv(
            withdrawalFee,
            1e18 - withdrawalFee,
            Math.Rounding.Down
        );

        shares += feeShares;

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
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

        uint256 feeShares = shares.mulDiv(
            uint256(fees.withdrawal),
            1e18,
            Math.Rounding.Down
        );

        assets = _convertToAssets(shares - feeShares, Math.Rounding.Up);

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        uint256 availableAmt = _convertToAssets(
            balanceOf(owner),
            Math.Rounding.Up
        );
        _burn(owner, shares);

        if (assets > _leftOver[owner]) {
            // console.log("Total Assets", totalAssets());
            // console.log("Assets", assets);
            // console.log("Available", availableAmt);
            // console.log("LeftOver", _leftOver[owner]);
            uint256 spentAssets;
            uint256 usedAssets;
            uint256 revisedAssets = assets;
            if (adapterCount <= availableAmt - assets) {
                revisedAssets += adapterCount;
            } else {
                revisedAssets += availableAmt - assets;
            }
            // console.log("Revised", revisedAssets);
            for (uint8 i; i < adapterCount; i++) {
                usedAssets = revisedAssets.mulDiv(
                    uint256(adapters[i].allocation),
                    1e18,
                    Math.Rounding.Down
                );
                // console.log("UsedAssets", usedAssets);
                // console.log("Adapter No", i);
                // console.log("Available", adapters[i].adapter.maxWithdraw(address(this)));
                adapters[i].adapter.withdraw(
                    usedAssets,
                    address(this),
                    address(this)
                );
                spentAssets += usedAssets;
            }
            _leftOver[owner] += revisedAssets - spentAssets;
        } else {
            _leftOver[owner] -= assets;
        }

        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return assets Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256 assets) {
        assets = IERC20(asset()).balanceOf(address(this));

        for (uint8 i; i < adapterCount; i++) {
            assets += adapters[i].adapter.convertToAssets(
                adapters[i].adapter.balanceOf(address(this))
            );
        }
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
            Math.Rounding.Down
        );
        shares = _convertToShares(assets, Math.Rounding.Down);
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
            Math.Rounding.Up
        );
        assets = _convertToAssets(shares, Math.Rounding.Up);
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
        shares = _convertToShares(assets, Math.Rounding.Up);

        uint256 withdrawalFee = uint256(fees.withdrawal);
        shares += shares.mulDiv(
            withdrawalFee,
            1e18 - withdrawalFee,
            Math.Rounding.Up
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
            Math.Rounding.Down
        );

        assets = _convertToAssets(shares - feeShares, Math.Rounding.Up);
    }

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256 shares) {
        return
            assets.mulDiv(
                totalSupply() + 10 ** decimalOffset,
                totalAssets() + 1,
                rounding
            );
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        return
            shares.mulDiv(
                totalAssets() + 1,
                totalSupply() + 10 ** decimalOffset,
                rounding
            );
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address. Delegates to adapters.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        if (paused() || assets >= depositLimit_) return 0;

        uint256 maxDeposit_ = depositLimit_;
        for (uint8 i; i < adapterCount; i++) {
            uint256 adapterMax = adapters[i].adapter.maxDeposit(address(this));
            uint256 scalar = 1e18 / uint256(adapters[i].allocation);

            if (adapterMax > type(uint256).max / scalar) {
                adapterMax = type(uint256).max;
            } else {
                adapterMax *= scalar;
            }

            maxDeposit_ = Math.min(maxDeposit_, adapterMax);
        }

        return maxDeposit_;
    }

    /// @return Maximum amount of vault shares that may be minted to given address. Delegates to adapters.
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        if (paused() || assets >= depositLimit_) return 0;

        uint256 maxMint_ = depositLimit >
            type(uint256).max / (totalSupply() + 10 ** decimalOffset)
            ? type(uint256).max
            : _convertToShares(depositLimit_, Math.Rounding.Up);

        for (uint8 i; i < adapterCount; i++) {
            uint256 adapterMax = adapters[i].adapter.maxMint(address(this));
            uint256 scalar = 1e18 / uint256(adapters[i].allocation);

            if (adapterMax > type(uint256).max / scalar) {
                adapterMax = type(uint256).max;
            } else {
                adapterMax *= scalar;
            }

            maxMint_ = Math.min(maxMint_, adapterMax);
        }

        return maxMint_;
    }

    /// @return Maximum amount of underlying `asset` token that can be withdrawn by `caller` address. Delegates to adapters.
    function maxWithdraw(address user) public view override returns (uint256) {
        uint256 maxWithdraw_ = type(uint256).max;
        uint256 leftover = _leftOver[user];

        for (uint8 i = 0; i < adapterCount; i++) {
            uint256 adapterMax = adapters[i].adapter.maxWithdraw(address(this));
            uint256 scalar = 1e18 / uint256(adapters[i].allocation);

            if (adapterMax > type(uint256).max / scalar) {
                adapterMax = type(uint256).max;
            } else {
                adapterMax *= scalar;
            }

            if (maxWithdraw_ == type(uint256).max) {
                maxWithdraw_ = adapterMax + leftover;
            } else if (adapterMax + leftover < type(uint256).max) {
                maxWithdraw_ = Math.max(maxWithdraw_, adapterMax + leftover);
            }
        }

        return maxWithdraw_;
    }

    /// @return Maximum amount of shares that may be redeemed by `caller` address. Delegates to adapters.
    function maxRedeem(address user) public view override returns (uint256) {
        uint256 maxRedeem_ = type(uint256).max;
        uint256 leftover = _leftOver[user] > 0
            ? _convertToShares(_leftOver[user], Math.Rounding.Down)
            : 0;

        for (uint8 i; i < adapterCount; i++) {
            uint256 adapterMax = adapters[i].adapter.maxRedeem(address(this));
            uint256 scalar = 1e18 / uint256(adapters[i].allocation);

            if (adapterMax > type(uint256).max / scalar) {
                adapterMax = type(uint256).max;
            } else {
                adapterMax *= scalar;
            }

            if (maxRedeem_ == type(uint256).max) {
                maxRedeem_ = adapterMax + leftover;
            } else if (adapterMax + leftover < type(uint256).max) {
                maxRedeem_ = Math.max(maxRedeem_, adapterMax + leftover);
            }
        }

        return maxRedeem_;
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
                    Math.Rounding.Down
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
                    Math.Rounding.Down
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
        uint256 managementFee = accruedManagementFee();
        uint256 totalFee = managementFee + accruedPerformanceFee();
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
                    Math.Rounding.Down
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
    function changeFees() external {
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
                          ADAPTER LOGIC
    //////////////////////////////////////////////////////////////*/

    AdapterConfig[10] public adapters;
    AdapterConfig[10] public proposedAdapters;

    uint8 public adapterCount;
    uint8 public proposedAdapterCount;

    uint256 public proposedAdapterTime;

    event NewAdaptersProposed(
        AdapterConfig[10] newAdapter,
        uint8 adapterCount,
        uint256 timestamp
    );
    event ChangedAdapters(
        AdapterConfig[10] oldAdapter,
        uint8 oldAdapterCount,
        AdapterConfig[10] newAdapter,
        uint8 newAdapterCount
    );

    error AssetInvalid();
    error InvalidConfig();

    /**
     * @notice Propose a new adapter for this vault. Caller must be Owner.
     * @param newAdapters A new ERC4626 that should be used as a yield adapter for this asset.
     * @param newAdapterCount Amount of new adapters.
     */
    function proposeAdapters(
        AdapterConfig[10] calldata newAdapters,
        uint8 newAdapterCount
    ) external onlyOwner {
        _verifyAdapterConfig(newAdapters, newAdapterCount);

        for (uint8 i; i < newAdapterCount; i++) {
            proposedAdapters[i] = newAdapters[i];
        }

        proposedAdapterCount = newAdapterCount;

        proposedAdapterTime = block.timestamp;

        emit NewAdaptersProposed(
            newAdapters,
            proposedAdapterCount,
            block.timestamp
        );
    }

    function _verifyAdapterConfig(
        AdapterConfig[10] calldata newAdapters,
        uint8 adapterCount_
    ) internal {
        if (adapterCount_ == 0 || adapterCount_ > 10) revert InvalidConfig();

        uint256 totalAllocation;
        for (uint8 i; i < adapterCount_; i++) {
            if (newAdapters[i].adapter.asset() != asset())
                revert AssetInvalid();

            uint256 allocation = uint256(newAdapters[i].allocation);
            if (allocation == 0) revert InvalidConfig();

            totalAllocation += allocation;
        }
        if (totalAllocation != 1e18) revert InvalidConfig();
    }

    /**
     * @notice Set a new Adapter for this Vault after the quit period has passed.
     * @dev This migration function will remove all assets from the old Vault and move them into the new vault
     * @dev Additionally it will zero old allowances and set new ones
     * @dev Last we update HWM and assetsCheckpoint for fees to make sure they adjust to the new adapter
     */
    function changeAdapters() external takeFees {
        if (
            proposedAdapterTime == 0 ||
            block.timestamp < proposedAdapterTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);

        for (uint8 i; i < adapterCount; i++) {
            adapters[i].adapter.redeem(
                adapters[i].adapter.balanceOf(address(this)),
                address(this),
                address(this)
            );

            IERC20(asset()).approve(address(adapters[i].adapter), 0);
        }

        emit ChangedAdapters(
            adapters,
            adapterCount,
            proposedAdapters,
            proposedAdapterCount
        );

        adapters = proposedAdapters;
        adapterCount = proposedAdapterCount;

        uint256 totalAssets_ = IERC20(asset()).balanceOf(address(this));

        for (uint8 i; i < adapterCount; i++) {
            IERC20(asset()).approve(
                address(adapters[i].adapter),
                type(uint256).max
            );

            adapters[i].adapter.deposit(
                totalAssets_.mulDiv(
                    uint256(adapters[i].allocation),
                    1e18,
                    Math.Rounding.Down
                ),
                address(this)
            );
        }

        delete proposedAdapters;
        delete proposedAdapterCount;
        delete proposedAdapterTime;
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
            block.timestamp < proposedAdapterTime + quitPeriod ||
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
