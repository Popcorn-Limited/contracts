// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";

library CurveV1Calls {

    function add_liquidity_one_coin(address strategyAdapter, uint256 amount, uint256 i, uint256 minAmount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature("add_liquidity_one_coin(uint256,uint256,uint256)", amount, i, minAmount)
        });
    }

    function remove_liquidity_one_coin(address strategyAdapter, uint256 token_amount, int128 i, uint256 min_amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,int128,uint256)", token_amount, i, min_amount
            )
        });
    }
}
