// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;

import { MultiCall } from "../../IGearboxV3.sol";
import { IAaveV2_LendingPoolAdapter } from "../IAdapter.sol";

library AaveV2 {
    function deposit(address strategyAdapter, address asset, uint256 amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IAaveV2_LendingPoolAdapter.deposit, (asset, amount, address(0), 0))
        });
    }

    function withdraw(address strategyAdapter, address asset, uint256 amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: strategyAdapter,
            callData: abi.encodeCall(IAaveV2_LendingPoolAdapter.withdraw, (asset, amount, address(0)))
        });
    }
}
