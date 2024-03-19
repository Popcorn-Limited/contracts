// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.17;

import {IConvexV1BaseRewardPoolAdapter} from "../../../interfaces/convex/IConvexV1BaseRewardPoolAdapter.sol";


library ConvexV1BaseRewardPool {
    function stake(address protocolAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.stake, (amount))
        });
    }

    function withdraw(address protocolAdapter, uint256 amount, bool claim)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.withdraw, (amount, claim))
        });
    }

    function getReward(address protocolAdapter) internal pure returns (MultiCall memory) {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IConvexV1BaseRewardPoolAdapter.getReward, ())
        });
    }
}
