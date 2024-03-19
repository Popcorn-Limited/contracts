// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;

import { MultiCall } from "../../IGearboxV3.sol";
import { IAsset, IBalancerV2VaultAdapter } from "../IAdapter.sol";

library BalancerV2 {

    function joinPoolSingleAsset(
        address strategyAdapter,
        bytes32 poolId,
        IAsset assetIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IBalancerV2VaultAdapter.joinPoolSingleAsset, (poolId, assetIn, amountIn, minAmountOut))
        });
    }

    function exitPoolSingleAsset(
        address strategyAdapter,
        bytes32 poolId,
        IAsset assetOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(
                IBalancerV2VaultAdapter.exitPoolSingleAsset, (poolId, assetOut, amountIn, minAmountOut)
                )
        });
    }
}
