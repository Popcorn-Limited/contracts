// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.17;

import {
    IAsset,
    SingleSwap,
    SingleSwapDiff,
    FundManagement,
    SwapKind,
    BatchSwapStep,
    JoinPoolRequest,
    ExitPoolRequest,
    IBalancerV2VaultAdapter
} from "../../../interfaces/balancer/IBalancerV2VaultAdapter.sol";

interface BalancerV2_Multicaller {}

library BalancerV2 {

    function joinPoolSingleAsset(
        address protocolAdapter,
        bytes32 poolId,
        IAsset assetIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IBalancerV2VaultAdapter.joinPoolSingleAsset, (poolId, assetIn, amountIn, minAmountOut))
        });
    }

    function exitPoolSingleAsset(
        address protocolAdapter,
        bytes32 poolId,
        IAsset assetOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(
                IBalancerV2VaultAdapter.exitPoolSingleAsset, (poolId, assetOut, amountIn, minAmountOut)
                )
        });
    }
}
