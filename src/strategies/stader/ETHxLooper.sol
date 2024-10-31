// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseAaveLeverageStrategy, LooperBaseValues, DataTypes, IERC20, Math} from "src/strategies/BaseAaveLeverageStrategy.sol";
import {IETHxStaking} from "./IETHxStaking.sol";
import {IWETH} from "src/interfaces/external/IWETH.sol";
import {ICurveMetapool} from "src/interfaces/external/curve/ICurveMetapool.sol";

struct LooperValues {
    address curvePool;
    address stakingPool;
}

contract ETHXLooper is BaseAaveLeverageStrategy {
    using Math for uint256;

    IETHxStaking public stakingPool; // stader pool for wrapping - converting

    // swap logic
    int128 private constant WETHID = 0;
    int128 private constant ETHxID = 1;

    ICurveMetapool public stableSwapPool;

    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) public initializer {
        (
            LooperBaseValues memory baseValues,
            LooperValues memory strategyValues
        ) = abi.decode(strategyInitData_, (LooperBaseValues, LooperValues));

        // init base leverage strategy
        __BaseLeverageStrategy_init(asset_, owner_, autoDeposit_, baseValues);

        // ethx pool
        stakingPool = IETHxStaking(strategyValues.stakingPool);

        // swap logic - curve
        stableSwapPool = ICurveMetapool(strategyValues.curvePool);
        IERC20(asset_).approve(address(stableSwapPool), type(uint256).max);
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;

        (uint256 borrowCap, uint256 supplyCap) = protocolDataProvider
            .getReserveCaps(asset());

        return (supplyCap * 1e18) - interestToken.totalSupply();
    }

    // provides conversion from eth to ethX
    function _toCollateralValue(
        uint256 ethAmount
    ) internal view override returns (uint256 ethXAmount) {
        uint256 ethxToEthRate = stakingPool.getExchangeRate();

        ethXAmount = ethAmount.mulDiv(1e18, ethxToEthRate, Math.Rounding.Ceil);
    }

    // provides conversion from ethX to eth
    function _toDebtValue(
        uint256 ethXAmount
    ) internal view override returns (uint256 ethAmount) {
        uint256 ethxToEthRate = stakingPool.getExchangeRate();

        ethAmount = ethXAmount.mulDiv(ethxToEthRate, 1e18, Math.Rounding.Ceil);
    }

    // swaps ethX to exact weth
    function _convertCollateralToDebt(
        uint256 amount,
        uint256 minAmount,
        address asset,
        uint256 assetsToWithdraw
    ) internal override {
        uint256 ethxToEthRate = stakingPool.getExchangeRate();

        // swap to ETH
        stableSwapPool.exchange(ETHxID, WETHID, amount, minAmount);

        // wrap precise amount of eth for flash loan repayment
        IWETH(address(borrowAsset)).deposit{value: minAmount}();

        // restake the eth needed to reach the ETHx amount the user is withdrawing
        uint256 missingETHx = assetsToWithdraw -
            IERC20(asset).balanceOf(address(this));
        if (missingETHx > 0) {
            uint256 missingETHAmount = missingETHx.mulDiv(
                ethxToEthRate,
                1e18,
                Math.Rounding.Ceil
            );

            // stake eth to receive ETHx
            stakingPool.deposit{value: missingETHAmount}(address(this));
        }
    }

    // unwrap weth and stakes into ethX
    function _convertDebtToCollateral(
        uint256 debtAmount,
        uint256 totCollateralAmount
    ) internal override {
        if (debtAmount > 0) IWETH(address(borrowAsset)).withdraw(debtAmount);

        stakingPool.deposit{value: totCollateralAmount}(address(this));
    }

    // assign balancer data for swaps
    function _setHarvestValues(bytes memory harvestValues) internal override {
        address curveSwapPool = abi.decode(harvestValues, (address));
        if (curveSwapPool != address(stableSwapPool)) {
            address asset_ = asset();

            // reset old pool
            IERC20(asset_).approve(address(stableSwapPool), 0);

            // set and approve new one
            stableSwapPool = ICurveMetapool(curveSwapPool);
            IERC20(asset_).approve(curveSwapPool, type(uint256).max);
        }
    }

    function _setEfficiencyMode() internal override {
        // eth correlated
        lendingPool.setUserEMode(uint8(1));
    }

    // reads max ltv on efficiency mode
    function _getMaxLTV() internal override returns (uint256 protocolMaxLTV) {
        // get protocol LTV
        DataTypes.EModeData memory emodeData = lendingPool.getEModeCategoryData(
            uint8(1)
        );
        protocolMaxLTV = uint256(emodeData.maxLTV) * 1e14; // make it 18 decimals to compare;
    }

    function _withdrawDust(address recipient) internal override {
        // send eth dust to recipient
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0 && totalSupply() == 0) {
            (bool sent, ) = address(recipient).call{
                value: address(this).balance
            }("");
            require(sent, "Failed to send eth");
        }

        // send ethX
        uint256 ethXBalance = IERC20(asset()).balanceOf(address(this));
        if (totalSupply() == 0 && ethXBalance > 0) {
            IERC20(asset()).transfer(recipient, ethXBalance);
        }
    }
}
