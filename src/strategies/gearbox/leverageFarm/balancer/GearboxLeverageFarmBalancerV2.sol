// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.25;

import {MultiCall} from "../IGearboxV3.sol";
import {GearboxLeverageFarm} from "../GearboxLeverageFarm.sol";
import {IAsset, IBalancerV2VaultAdapter} from "../IGearboxStrategyAdapter.sol";

contract GearboxLeverageFarmBalancerV2 is GearboxLeverageFarm {
    function _gearboxStrategyDeposit(bytes memory data) internal override {
        (bytes32 poolId, IAsset assetIn, uint256 amountIn, uint256 minAmountOut) =
            abi.decode(data, (bytes32, IAsset, uint256, uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IBalancerV2VaultAdapter.joinPoolSingleAsset, (poolId, assetIn, amountIn, minAmountOut))
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _gearboxStrategyWithdraw(bytes memory data) internal override {
        (bytes32 poolId, IAsset assetOut, uint256 amountIn, uint256 minAmountOut) =
            abi.decode(data, (bytes32, IAsset, uint256, uint256));

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(
                IBalancerV2VaultAdapter.exitPoolSingleAsset, (poolId, assetOut, amountIn, minAmountOut)
            )
        });

        creditFacade.multicall(creditAccount, calls);
    }
}
