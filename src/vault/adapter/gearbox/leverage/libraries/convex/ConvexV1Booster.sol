// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.17;

import {IConvexV1BoosterAdapter} from "../../../interfaces/convex/IConvexV1BoosterAdapter.sol";

library ConvexV1Booster {
    function deposit(address protocolAdapter, uint256 pid, uint256 amount, bool stake)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IConvexV1BoosterAdapter.deposit, (pid, amount, stake))
        });
    }

    function withdraw(address protocolAdapter, uint256 pid, uint256 amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IConvexV1BoosterAdapter.withdraw, (pid, amount))
        });
    }
}
