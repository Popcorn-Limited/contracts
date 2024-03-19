// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";
import { IConvexV1BaseRewardPoolAdapter } from "../IAdapter.sol";

library ConvexV1BaseRewardPool {
    function stake(address strategyAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.stake, (amount))
        });
    }

    function withdraw(address strategyAdapter, uint256 amount, bool claim)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdraw, (amount, claim))
        });
    }

    function getReward(address strategyAdapter) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.getReward, ())
        });
    }
}
