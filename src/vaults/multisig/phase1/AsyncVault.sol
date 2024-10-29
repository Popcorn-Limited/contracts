// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseControlledAsyncRedeem} from "./BaseControlledAsyncRedeem.sol";
import {BaseERC7540} from "./BaseERC7540.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

struct InitializeParams {
    address asset;
    string name;
    string symbol;
    address owner;
    Limits limits;
    Fees fees;
}

struct Bounds {
    uint256 upper;
    uint256 lower;
}

struct Limits {
    uint256 depositLimit;
    uint256 minAmount;
}

struct Fees {
    uint64 performanceFee;
    uint64 managementFee;
    uint64 withdrawalIncentive;
    uint64 feesUpdatedAt;
    uint256 highWaterMark;
    address feeRecipient;
}

abstract contract AsyncVault is BaseControlledAsyncRedeem {
    using FixedPointMathLib for uint256;

    error ZeroAmount();
    error Misconfigured();

    constructor(
        InitializeParams memory params
    ) BaseERC7540(params.owner, params.asset, params.name, params.symbol) {
        _setLimits(params.limits);
        _setFees(params.fees);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // Override to add minAmount check (Which is used in mint and will revert the function)
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        uint256 shares = convertToShares(assets);
        return shares < limits.minAmount ? 0 : shares;
    }

    // Override to add minAmount check (Which is used in deposit and will revert the function)
    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        if (shares < limits.minAmount) return 0;

        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

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

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = limits.depositLimit;
        return (paused || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address.
    /// @dev overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = limits.depositLimit;

        if (paused || assets >= depositLimit_) return 0;
        if (depositLimit_ == type(uint256).max) return depositLimit_;

        return convertToShares(depositLimit_ - assets);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets) external returns (uint256) {
        return deposit(assets, msg.sender);
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    function withdraw(uint256 assets) external returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    function requestRedeem(
        uint256 shares,
        address recipient,
        address owner
    ) external override returns (uint256 requestId) {
        require(shares >= limits.minAmount, "ERC7540Vault/min-amount");

        return _requestRedeem(shares, recipient, owner);
    }

    function fulfillRedeem(
        uint256 shares,
        address controller
    ) external override returns (uint256) {
        uint256 assets = convertToLowBoundAssets(shares);

        _fulfillRedeem(
            assets.mulDivDown(1e18 - uint256(fees.withdrawalIncentive), 1e18),
            shares,
            controller
        );

        return assets;
    }

    function fulfillMultipleRedeems(
        uint256[] memory shares,
        address[] memory controllers
    ) external returns (uint256) {
        if (shares.length != controllers.length) revert Misconfigured();
        uint256 withdrawalIncentive = uint256(fees.withdrawalIncentive);

        uint256 total;
        for (uint256 i; i < shares.length; i++) {
            uint256 assets = convertToLowBoundAssets(shares[i]);
            total += assets;

            _fulfillRedeem(
                assets.mulDivDown(1e18 - withdrawalIncentive, 1e18),
                shares[i],
                controllers[i]
            );
        }
        return total;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256) internal virtual override {
        if (!paused) _takeFees();
    }

    function afterDeposit(uint256 assets, uint256) internal virtual override {
        _requireNotPaused();
    }

    /*//////////////////////////////////////////////////////////////
                            YIELD RATE LOGIC
    //////////////////////////////////////////////////////////////*/

    Bounds public bounds;

    event BoundsUpdated(Bounds prev, Bounds next);

    function getBounds() public view returns (Bounds memory) {
        return bounds;
    }

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

    event FeesUpdated(Fees prev, Fees next);

    error InvalidFee(uint256 fee);

    function getFees() public view returns (Fees memory) {
        return fees;
    }

    function accruedFees() public view returns (uint256) {
        Fees memory fees_ = fees;

        return _accruedFees(fees_);
    }

    function _accruedFees(Fees memory fees_) internal view returns (uint256) {
        return _accruedPerformanceFee(fees_) + _accruedManagementFee(fees_);
    }

    /**
     * @notice Performance fee that has accrued since last fee harvest.
     * @return Accrued performance fee in underlying `asset` token.
     * @dev Performance fee is based on a high water mark value. If vault share value has increased above the
     *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
     */
    function _accruedPerformanceFee(
        Fees memory fees_
    ) internal view returns (uint256) {
        uint256 shareValue = convertToAssets(1e18);
        uint256 performanceFee = uint256(fees_.performanceFee);
        uint256 highWaterMark = fees_.highWaterMark;

        return
            performanceFee > 0 && shareValue > highWaterMark
                ? performanceFee.mulDivUp(
                    (shareValue - highWaterMark) * totalSupply,
                    1e36
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

    function setFees(Fees memory fees_) public onlyOwner whenNotPaused {
        _takeFees();

        _setFees(fees_);
    }

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
        fees_.highWaterMark = convertToAssets(1e18);

        emit FeesUpdated(fees, fees_);

        fees = fees_;
    }

    function takeFees() external whenNotPaused {
        _takeFees();
    }

    function _takeFees() internal {
        Fees memory fees_ = fees;
        uint256 fee = _accruedFees(fees_);
        uint256 shareValue = convertToAssets(1e18);

        if (shareValue > fees_.highWaterMark) fees.highWaterMark = shareValue;

        if (fee > 0) _mint(fees_.feeRecipient, convertToShares(fee));

        fees.feesUpdatedAt = uint64(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    Limits public limits;

    event LimitsUpdated(Limits prev, Limits next);

    function setLimits(Limits memory limits_) external onlyOwner {
        _setLimits(limits_);
    }

    function _setLimits(Limits memory limits_) internal {
        emit LimitsUpdated(limits, limits_);

        limits = limits_;
    }
}
