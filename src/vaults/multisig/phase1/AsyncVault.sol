// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseControlledAsyncRedeem} from "./BaseControlledAsyncRedeem.sol";
import {BaseERC7540, ERC20} from "./BaseERC7540.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @notice Handles the initialize parameters of the vault
struct InitializeParams {
    /// @notice The address of the asset that the vault will manage
    address asset;
    /// @notice The name of the vault
    string name;
    /// @notice The symbol of the vault
    string symbol;
    /// @notice The trusted manager of the vault (handles all sensitive management logic)
    address owner;
    /// @notice The limits of the vault
    Limits limits;
    /// @notice The fees of the vault
    Fees fees;
}

/// @notice Stores the bounds of the vault
struct Bounds {
    /// @notice Upper bound of the vault (will be used for future profit calculations of the manager)
    uint256 upper;
    /// @notice Lower bound of the vault (used on withdrawals to ensure an additional asset buffer between the reported totalAssets and the actual totalAssets)
    uint256 lower;
}

/// @notice Stores the deposit limit and minAmounts of the vault
struct Limits {
    /// @notice Maximum amount of assets that can be deposited into the vault
    uint256 depositLimit;
    /// @notice Minimum amount of shares that can be minted / redeemed from the vault
    uint256 minAmount;
}

/// @notice Stores all fee related variables
struct Fees {
    /// @notice Performance fee rate in 1e18 (100% = 1e18)
    uint64 performanceFee;
    /// @notice Management fee rate in 1e18 (100% = 1e18)
    uint64 managementFee;
    /// @notice Withdrawal incentive fee rate in 1e18 (100% = 1e18)
    uint64 withdrawalIncentive;
    /// @notice Timestamp of the last time the fees were updated (used for management fee calculations)
    uint64 feesUpdatedAt;
    /// @notice Address of the fee recipient
    address feeRecipient;
}

/**
 * @title   AsyncVault
 * @author  RedVeil
 * @notice  Abstract contract containing reusable logic that are the basis of ERC-7540 compliant async redeem vauls
 * @notice  Besides the basic logic for ERC-7540 this contract contains most other logic to manage a modern DeFi vault
 * @dev     Logic to account and manage assets must be implemented by inheriting contracts
 */
abstract contract AsyncVault is BaseControlledAsyncRedeem {
    using FixedPointMathLib for uint256;

    error ZeroAmount();
    error Misconfigured();

    /**
     * @notice Constructor for AsyncVault
     * @param params The initialization parameters
     */
    constructor(
        InitializeParams memory params
    ) BaseERC7540(params.owner, params.asset, params.name, params.symbol) {
        _setLimits(params.limits);
        _setFees(params.fees);

        highWaterMark = convertToAssets(10 ** asset.decimals());
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into the vault
     * @param assets The amount of assets to deposit
     * @return shares The amount of shares required
     */
    function deposit(uint256 assets) external returns (uint256) {
        return deposit(assets, msg.sender);
    }

    /**
     * @notice Mint shares into the vault
     * @param shares The amount of shares to mint
     * @return assets The amount of assets received
     */
    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    /**
     * @notice Withdraw assets from the vault
     * @param assets The amount of assets to withdraw
     * @return shares The amount of shares required
     */
    function withdraw(uint256 assets) external returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    /**
     * @notice Redeem shares from the vault
     * @param shares The amount of shares to redeem
     * @return assets The amount of assets received
     */
    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Simulates a deposit into the vault and returns the amount of shares that would be received by the user
     * @param assets The amount of assets to deposit
     * @return shares The amount of shares that would be received by the user
     * @dev This function will return 0 if the vault is paused or if the deposit doesnt meet the limits
     */
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        Limits memory limits_ = limits;
        uint256 shares = convertToShares(assets);

        if (
            paused ||
            totalAssets() + assets > limits_.depositLimit ||
            shares < limits_.minAmount
        ) return 0;

        return super.previewDeposit(assets);
    }

    /**
     * @notice Simulates a mint into the vault and returns the amount of assets required to mint the given amount of shares
     * @param shares The amount of shares to mint
     * @return assets The amount of assets required to mint the given amount of shares
     * @dev This function will return 0 if the vault is paused or if the mint doesnt meet the limits
     */
    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        Limits memory limits_ = limits;
        uint256 assets = convertToAssets(shares);

        if (
            paused ||
            totalAssets() + assets > limits_.depositLimit ||
            shares < limits_.minAmount
        ) return 0;

        return super.previewMint(shares);
    }

    /**
     * @notice Converts shares to assets based on a lower bound of totalAssets
     * @param shares The amount of shares to convert
     * @return lowerTotalAssets The lower bound value of assets that correspond to the given amount of shares
     * @dev This function is used on redeem fulfillment to ensure an additional asset buffer between the reported totalAssets and the actual totalAssets.
     * In most cases this will be the same as `convertToAssets` but same vaults might need to add a small buffer if they use volatile strategies or assets that are hard to sell.
     */
    function convertToLowBoundAssets(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        uint256 assets = totalAssets().mulDivDown(1e18 - bounds.lower, 1e18);

        return supply == 0 ? shares : shares.mulDivDown(assets, supply);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the vault
     * @return assetsThe maxDeposit of the controller
     * @dev Will return 0 if the vault is paused or if the deposit limit is reached
     */
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = limits.depositLimit;
        return (paused || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }
    /**
     * @notice Returns the maximum amount of shares that can be minted into the vault
     * @return shares The maxMint of the controller
     * @dev Will return 0 if the vault is paused or if the deposit limit is reached
     * @dev Overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
     */
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = limits.depositLimit;

        if (paused || assets >= depositLimit_) return 0;
        if (depositLimit_ == type(uint256).max) return depositLimit_ - totalSupply;

        return convertToShares(depositLimit_ - assets);
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Requests a redeem for the caller
     * @param shares The amount of shares to redeem
     * @return requestId The requestId of the redeem request
     */
    function requestRedeem(uint256 shares) external returns (uint256) {
        return requestRedeem(shares, msg.sender, msg.sender);
    }

    /**
     * @notice Requests a redeem of shares from the vault
     * @param shares The amount of shares to redeem
     * @param controller The user that will be receiving pending shares
     * @param owner The owner of the shares to redeem
     * @return requestId The requestId of the redeem request
     * @dev This redeem request is added to any pending redeem request of the controller
     * @dev This function will revert if the shares are less than the minAmount
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public override returns (uint256 requestId) {
        require(shares >= limits.minAmount, "ERC7540Vault/min-amount");

        return _requestRedeem(shares, controller, owner);
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fulfills a redeem request of the controller to allow the controller to withdraw their assets
     * @param shares The amount of shares to redeem
     * @param controller The controller to redeem for
     * @return assets The amount of assets received
     * @dev This function will revert if the shares are less than the minAmount
     * @dev This function will also take the withdrawal incentive fee from the assets to incentivse the manager to fulfill the request
     */
    function fulfillRedeem(
        uint256 shares,
        address controller
    ) external override returns (uint256 assets) {
        // Using the lower bound totalAssets ensures that even with volatile strategies and market conditions we will have sufficient assets to cover the redeem
        assets = convertToLowBoundAssets(shares);

        // Calculate the withdrawal incentive fee from the assets
        Fees memory fees_ = fees;
        uint256 fees = assets.mulDivDown(
            uint256(fees_.withdrawalIncentive),
            1e18
        );

        // Fulfill the redeem request
        _fulfillRedeem(assets - fees, shares, controller);

        // Send the withdrawal incentive fee to the fee recipient
        handleWithdrawalIncentive(fees, fees_.feeRecipient);
    }

    /**
     * @notice Fulfills multiple redeem requests of the controller to allow the controller to withdraw their assets
     * @param shares The amount of shares to redeem
     * @param controllers The controllers to redeem for
     * @return total The total amount of assets received
     * @dev This function will revert if the shares and controllers arrays are not the same length
     * @dev This function will also take the withdrawal incentive fee from the assets to incentivse the manager to fulfill the requests
     */
    function fulfillMultipleRedeems(
        uint256[] memory shares,
        address[] memory controllers
    ) external returns (uint256 total) {
        if (shares.length != controllers.length) revert Misconfigured();

        // cache the fees
        Fees memory fees_ = fees;

        uint256 totalFees;
        for (uint256 i; i < shares.length; i++) {
            // Using the lower bound totalAssets ensures that even with volatile strategies and market conditions we will have sufficient assets to cover the redeem
            uint256 assets = convertToLowBoundAssets(shares[i]);

            // Calculate the withdrawal incentive fee from the assets
            uint256 fees = assets.mulDivDown(
                uint256(fees_.withdrawalIncentive),
                1e18
            );

            // Fulfill the redeem request
            _fulfillRedeem(assets - fees, shares[i], controllers[i]);

            // Add to the total assets and fees
            total += assets;
            totalFees += fees;
        }

        // Send the withdrawal incentive fee to the fee recipient
        handleWithdrawalIncentive(totalFees, fees_.feeRecipient);

        return total;
    }

    /**
     * @notice Handles the withdrawal incentive fee by sending it to the fee recipient
     * @param fee The amount of fee to send
     * @param feeRecipient The address to send the fee to
     * @dev This function is expected to be overriden in inheriting contracts
     */
    function handleWithdrawalIncentive(
        uint256 fee,
        address feeRecipient
    ) internal virtual {
        if (fee > 0) SafeTransferLib.safeTransfer(asset, feeRecipient, fee);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Takes fees before a withdraw (if the contract is not paused)
     * @dev This function is expected to be overriden in inheriting contracts
     */
    function beforeWithdraw(uint256 assets, uint256) internal virtual override {
        if (!paused) _takeFees();
    }

    /**
     * @notice Takes fees before a deposit
     * @dev This function is expected to be overriden in inheriting contracts
     */
    function afterDeposit(uint256 assets, uint256) internal virtual override {
        // deposit and mint already have the `whenNotPaused` modifier so we don't need to check it here
        _takeFees();
    }

    /*//////////////////////////////////////////////////////////////
                            BOUND LOGIC
    //////////////////////////////////////////////////////////////*/

    Bounds public bounds;

    event BoundsUpdated(Bounds prev, Bounds next);

    /// @notice Returns the bounds of the vault
    function getBounds() public view returns (Bounds memory) {
        return bounds;
    }

    /**
     * @notice Sets the bounds of the vault to ensure that even with volatile strategies and market conditions we will have sufficient assets to cover the redeem
     * @param bounds_ The bounds to set
     * @dev This function will revert if the bounds are greater than or equal to 1e18
     */
    function setBounds(Bounds memory bounds_) external onlyOwner {
        if (bounds_.lower >= 1e18 || bounds_.upper >= 1e18)
            revert Misconfigured();

        emit BoundsUpdated(bounds, bounds_);

        bounds = bounds_;
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    Fees public fees;

    /// @notice High water mark of the vault (used for performance fee calculations)
    uint256 public highWaterMark;

    event FeesUpdated(Fees prev, Fees next);

    error InvalidFee(uint256 fee);

    /// @notice Returns the fees parameters of the vault
    function getFees() public view returns (Fees memory) {
        return fees;
    }

    /// @notice Returns the accrued fees of the vault
    function accruedFees() public view returns (uint256) {
        Fees memory fees_ = fees;

        return _accruedFees(fees_);
    }

    /// @dev Internal function to calculate the accrued fees
    function _accruedFees(Fees memory fees_) internal view returns (uint256) {
        return _accruedPerformanceFee(fees_) + _accruedManagementFee(fees_);
    }

    /**
     * @notice Performance fee that has accrued since last fee harvest.
     * @return accruedPerformanceFee In underlying `asset` token.
     * @dev Performance fee is based on a high water mark value. If vault share value has increased above the
     *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
     */
    function _accruedPerformanceFee(
        Fees memory fees_
    ) internal view returns (uint256) {
        uint256 shareValue = convertToAssets(10 ** asset.decimals());
        uint256 performanceFee = uint256(fees_.performanceFee);

        return
            performanceFee > 0 && shareValue > highWaterMark
                ? performanceFee.mulDivUp(
                    (shareValue - highWaterMark) * totalSupply,
                    (10 ** (18 + asset.decimals()))
                )
                : 0;
    }

    /**
     * @notice Management fee that has accrued since last fee harvest.
     * @return accruedManagementFee In underlying `asset` token.
     * @dev Management fee is annualized per minute, based on 525,600 minutes per year. Total assets are calculated using
     *  the average of their current value and the value at the previous fee harvest checkpoint. This method is similar to
     *  calculating a definite integral using the trapezoid rule.
     */
    function _accruedManagementFee(
        Fees memory fees_
    ) internal view returns (uint256) {
        uint256 managementFee = uint256(fees_.managementFee);

        return
            managementFee > 0
                ? managementFee.mulDivDown(
                    totalAssets() * (block.timestamp - fees_.feesUpdatedAt),
                    365.25 days // seconds per year
                ) / 1e18
                : 0;
    }

    /**
     * @notice Sets the fees of the vault
     * @param fees_ The fees to set
     * @dev This function will revert if the fees are greater than 20% performanceFee, 5% managementFee, or 5% withdrawalIncentive
     * @dev This function will also take the fees before setting them to ensure the new fees rates arent applied to any pending fees
     */
    function setFees(Fees memory fees_) public onlyOwner whenNotPaused {
        _takeFees();

        _setFees(fees_);
    }

    /// @dev Internal function to set the fees
    function _setFees(Fees memory fees_) internal {
        // Dont take more than 20% performanceFee, 5% managementFee, 5% withdrawalIncentive
        if (
            fees_.performanceFee > 2e17 ||
            fees_.managementFee > 5e16 ||
            fees_.withdrawalIncentive > 5e16
        ) revert Misconfigured();
        if (fees_.feeRecipient == address(0)) revert Misconfigured();

        // Dont rely on user input here
        fees_.feesUpdatedAt = uint64(block.timestamp);

        emit FeesUpdated(fees, fees_);

        fees = fees_;
    }

    /**
     * @notice Mints fees as shares of the vault to the fee recipient
     * @dev It will also update the all other fee related variables
     */
    function takeFees() external whenNotPaused {
        _takeFees();
    }

    /// @dev Internal function to take the fees
    function _takeFees() internal {
        Fees memory fees_ = fees;
        uint256 fee = _accruedFees(fees_);
        uint256 shareValue = convertToAssets(10 ** asset.decimals());

        if (shareValue > highWaterMark) highWaterMark = shareValue;

        if (fee > 0) _mint(fees_.feeRecipient, convertToShares(fee));

        fees.feesUpdatedAt = uint64(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    Limits public limits;

    event LimitsUpdated(Limits prev, Limits next);

    /**
     * @notice Sets the deposit limit and minAmounts of the vault to limit user exposure to strategy risks
     * @param limits_ The limits to set
     */
    function setLimits(Limits memory limits_) external onlyOwner {
        _setLimits(limits_);
    }

    /// @dev Internal function to set the limits
    function _setLimits(Limits memory limits_) internal {
        // TODO this can lock user deposits if lowered too much
        emit LimitsUpdated(limits, limits_);

        limits = limits_;
    }
}
