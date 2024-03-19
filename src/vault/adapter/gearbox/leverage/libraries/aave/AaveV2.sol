// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;

import {IAaveV2_LendingPoolAdapter} from "../../../interfaces/aave/IAaveV2_LendingPoolAdapter.sol";

interface AaveV2_LendingPoolMulticaller {}

library AaveV2 {
    function deposit(address protocolAdapter, address asset, uint256 amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IAaveV2_LendingPoolAdapter.deposit, (asset, amount, address(0), 0))
        });
    }

    function withdraw(address protocolAdapter, address asset, uint256 amount)
        internal
        pure
        returns (MultiCall memory)
    {
        return MultiCall({
            target: protocolAdapter,
            callData: abi.encodeCall(IAaveV2_LendingPoolAdapter.withdraw, (asset, amount, address(0)))
        });
    }
}
