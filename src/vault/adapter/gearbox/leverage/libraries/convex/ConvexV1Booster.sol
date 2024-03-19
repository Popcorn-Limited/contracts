// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";
import { IConvexV1BoosterAdapter } from "../IAdapter.sol";

library ConvexV1Booster {
    function deposit(address strategyAdapter, uint256 pid, uint256 amount, bool stake)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BoosterAdapter.deposit, (pid, amount, stake))
        });
    }

    function withdraw(address strategyAdapter, uint256 pid, uint256 amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IConvexV1BoosterAdapter.withdraw, (pid, amount))
        });
    }
}
