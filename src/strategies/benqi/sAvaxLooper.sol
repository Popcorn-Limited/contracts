// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseCompoundV2LeverageStrategy, LooperBaseValues, IERC20, Math} from "src/strategies/BaseCompV2LeverageStrategy.sol";
import {IAvaxStaking} from "./IAvaxStaking.sol";
import {IWETH as IWAVAX} from "src/interfaces/external/IWETH.sol";
import {IBalancerVault, SwapKind, SingleSwap, FundManagement} from "src/interfaces/external/balancer/IBalancer.sol";

struct LooperValues {
    address balancerVault;
    bytes32 poolId;
}

contract sAVAXLooper is BaseCompoundV2LeverageStrategy {
    using Math for uint256;

    // swap logic
    IBalancerVault public balancerVault;
    bytes32 public balancerPoolId;
    IAvaxStaking public sAVAX;

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

        sAVAX = IAvaxStaking(asset_);

        // swap logic - balancer
        balancerPoolId = strategyValues.poolId;
        balancerVault = IBalancerVault(strategyValues.balancerVault);
        IERC20(asset_).approve(address(balancerVault), type(uint256).max);
    }

    // provides conversion from avax to sAvax
    function _toCollateralValue(
        uint256 avaxAmount
    ) internal view override returns (uint256 sAvax) {
        sAvax = sAVAX.getSharesByPooledAvax(avaxAmount);
    }

    // provides conversion from sAvax to Avax
    function _toDebtValue(
        uint256 sAvaxAmount
    ) internal view override returns (uint256 avaxAmount) {
        avaxAmount = sAVAX.getPooledAvaxByShares(sAvaxAmount);
    }

    // sAVAX to exact wAVAX
    function _convertCollateralToDebt(
        uint256 maxCollateralIn,
        uint256 exactDebtAmont,
        address asset,
        uint256
    ) internal override {
        // swap to exact wAVAX on balancer
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

    // unwrap wAVAX and stakes into sAvax
    function _convertDebtToCollateral(
        uint256 debtAmount,
        uint256 totCollateralAmount
    ) internal override {
        if (debtAmount > 0) IWAVAX(address(borrowAsset)).withdraw(debtAmount);

        // stake borrowed Avax and receive sAvax
        sAVAX.submit{value:totCollateralAmount}();
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

    function _withdrawDust(address recipient) internal override {
        // send Avax dust to recipient
        uint256 avaxBalance = address(this).balance;
        if (avaxBalance > 0 && totalSupply() == 0) {
            (bool sent, ) = address(recipient).call{
                value: address(this).balance
            }("");
            require(sent, "Failed to send Avax");
        }

        // send sAvax
        uint256 sAvaxBalance = IERC20(asset()).balanceOf(address(this));
        if (totalSupply() == 0 && sAvaxBalance > 0) {
            IERC20(asset()).transfer(recipient, sAvaxBalance);
        }
    }
}
