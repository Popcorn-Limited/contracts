// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseAaveLeverageStrategy, LooperBaseValues, DataTypes, IERC20} from "src/strategies/BaseAaveLeverageStrategy.sol";
import {IMaticXPool} from "./IMaticX.sol";
import {IWETH as IWMatic} from "src/interfaces/external/IWETH.sol";
import {IBalancerVault, SwapKind, SingleSwap, FundManagement} from "src/interfaces/external/balancer/IBalancer.sol";

struct LooperValues {
    address balancerVault;
    address maticXPool;
    bytes32 poolId;
}

contract MaticXLooper is BaseAaveLeverageStrategy {
    IMaticXPool public maticXPool; // stader pool for wrapping - converting

    // swap logic
    IBalancerVault public balancerVault;
    bytes32 public balancerPoolId;

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

        // maticX pool as oracle
        maticXPool = IMaticXPool(strategyValues.maticXPool);

        // balancer - swap logic
        balancerPoolId = strategyValues.poolId;
        balancerVault = IBalancerVault(strategyValues.balancerVault);
        IERC20(asset_).approve(address(balancerVault), type(uint256).max);
    }

    // provides conversion from matic to maticX
    function _toCollateralValue(
        uint256 maticAmount
    ) internal view override returns (uint256 maticXAmount) {
        (maticXAmount, , ) = maticXPool.convertMaticToMaticX(maticAmount);
    }

    // provides conversion from maticX to matic
    function _toDebtValue(
        uint256 maticXAmount
    ) internal view override returns (uint256 maticAmount) {
        (maticAmount, , ) = maticXPool.convertMaticXToMatic(maticXAmount);
    }

    // swaps MaticX to exact wMatic
    function _convertCollateralToDebt(
        uint256 maxCollateralIn,
        uint256 exactDebtAmont,
        address asset
    ) internal override {
        SingleSwap memory swap = SingleSwap(
            balancerPoolId,
            SwapKind.GIVEN_OUT,
            asset,
            address(borrowAsset),
            exactDebtAmont,
            hex""
        );

        balancerVault.swap(
            swap,
            FundManagement(address(this), false, payable(address(this)), false),
            maxCollateralIn,
            block.timestamp
        );
    }

    // unwrap wMatic and stakes into maticX
    function _convertDebtToCollateral(
        uint256 debtAmount,
        uint256 totCollateralAmount
    ) internal override {
        if (debtAmount > 0) IWMatic(address(borrowAsset)).withdraw(debtAmount);

        maticXPool.swapMaticForMaticXViaInstantPool{
            value: totCollateralAmount
        }();
    }

    // assign balancer data for swaps
    function _setHarvestValues(bytes memory harvestValues) internal override {
        (address newBalancerVault, bytes32 newBalancerPoolId) = abi.decode(
            harvestValues,
            (address, bytes32)
        );

        if (newBalancerVault != address(balancerVault)) {
            address asset_ = asset();

            // reset old pool
            IERC20(asset_).approve(address(balancerVault), 0);

            // set and approve new one
            balancerVault = IBalancerVault(newBalancerVault);
            IERC20(asset_).approve(newBalancerVault, type(uint256).max);
        }

        if (newBalancerPoolId != balancerPoolId)
            balancerPoolId = newBalancerPoolId;
    }

    function _setEfficiencyMode() internal override {
        // Matic correlated
        lendingPool.setUserEMode(uint8(2));
    }

    // reads max ltv on efficiency mode
    function _getMaxLTV() internal override returns (uint256 protocolMaxLTV) {
        // get protocol LTV
        DataTypes.EModeData memory emodeData = lendingPool.getEModeCategoryData(
            uint8(2)
        );
        protocolMaxLTV = uint256(emodeData.maxLTV) * 1e14; // make it 18 decimals to compare;
    }

    function _withdrawDust(address recipient) internal override {
        // send matic dust to recipient
        uint256 maticBalance = address(this).balance;
        if (maticBalance > 0) {
            (bool sent, ) = address(recipient).call{
                value: address(this).balance
            }("");
            require(sent, "Failed to send Matic");
        }

        // send maticX
        uint256 maticXBalance = IERC20(asset()).balanceOf(address(this));
        if (totalSupply() == 0 && maticXBalance > 0) {
            IERC20(asset()).transfer(recipient, maticXBalance);
        }
    }
}
