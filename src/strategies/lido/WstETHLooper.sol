// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseAaveLeverageStrategy, LooperBaseValues, DataTypes, IERC20, Math} from "src/strategies/BaseAaveLeverageStrategy.sol";
import {IwstETH} from "./IwstETH.sol";
import {IWETH} from "src/interfaces/external/IWETH.sol";
import {ILido} from "./ILido.sol";
import {ICurveMetapool} from "src/interfaces/external/curve/ICurveMetapool.sol";

struct LooperValues {
    address curvePool;
}

contract WstETHLooper is BaseAaveLeverageStrategy {
    using Math for uint256;

    // swap logic
    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;

    ICurveMetapool public stableSwapPool;
    address public constant stETH =
        address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

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

        // swap logic - curve
        stableSwapPool = ICurveMetapool(strategyValues.curvePool);
        IERC20(stETH).approve(address(stableSwapPool), type(uint256).max);
    }

    // provides conversion from ETH to wstETH
    function _toCollateralValue(
        uint256 ethAmount
    ) internal view override returns (uint256 wstETHAmount) {
        wstETHAmount = ILido(stETH).getSharesByPooledEth(ethAmount);
    }

    // provides conversion from wstETH to ETH
    function _toDebtValue(
        uint256 wstETHAmount
    ) internal view override returns (uint256 ethAmount) {
        ethAmount = ILido(stETH).getPooledEthByShares(wstETHAmount);
    }

    // wstETH to exact weth
    function _convertCollateralToDebt(
        uint256 amount,
        uint256 minAmount,
        address asset,
        uint256 assetsToWithdraw
    ) internal override {
        // unwrap wstETH into stETH
        uint256 stETHAmount = IwstETH(asset).unwrap(amount);

        // swap to ETH
        stableSwapPool.exchange(STETHID, WETHID, stETHAmount, minAmount);

        // wrap precise amount of ETH for flash loan repayment
        IWETH(address(borrowAsset)).deposit{value: minAmount}();

        // restake the eth needed to reach the wstETH amount the user is withdrawing
        uint256 missingWstETH = assetsToWithdraw -
            IERC20(asset).balanceOf(address(this)) +
            1;
        if (missingWstETH > 0) {
            uint256 ethAmount = _toDebtValue(missingWstETH);

            // stake eth to receive wstETH
            (bool sent, ) = asset.call{value: ethAmount}("");
            require(sent, "Fail to send eth to wstETH");
        }
    }

    // unwrap weth and stakes into wstETH
    function _convertDebtToCollateral(
        uint256 debtAmount,
        uint256 totCollateralAmount
    ) internal override {
        if (debtAmount > 0) IWETH(address(borrowAsset)).withdraw(debtAmount);

        // stake borrowed eth and receive wstETH
        (bool sent, ) = asset().call{value: totCollateralAmount}("");
        require(sent, "Fail to send eth to wstETH");
    }

    // assign balancer data for swaps
    function _setHarvestValues(bytes memory harvestValues) internal override {
        address curveSwapPool = abi.decode(harvestValues, (address));
        if (curveSwapPool != address(stableSwapPool)) {
            // reset old pool
            IERC20(stETH).approve(address(stableSwapPool), 0);

            // set and approve new one
            stableSwapPool = ICurveMetapool(curveSwapPool);
            IERC20(stETH).approve(address(stableSwapPool), type(uint256).max);
        }
    }

    function _setEfficiencyMode() internal override {
        // ETH correlated
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
        // send ETH dust to recipient
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0 && totalSupply() == 0) {
            (bool sent, ) = address(recipient).call{
                value: address(this).balance
            }("");
            require(sent, "Failed to send ETH");
        }

        // send wstETH
        uint256 wstETHBalance = IERC20(asset()).balanceOf(address(this));
        if (totalSupply() == 0 && wstETHBalance > 0) {
            IERC20(asset()).transfer(recipient, wstETHBalance);
        }
    }
}
