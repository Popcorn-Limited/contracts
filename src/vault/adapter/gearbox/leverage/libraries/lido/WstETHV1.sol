// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;

import { MultiCall } from "../../IGearboxV3.sol";
import { IwstETHV1Adapter } from "../IAdapter.sol";

library WstETHV1_Calls {
    function wrap(address strategyAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({target: strategyAdapter, callData: abi.encodeCall(IwstETHV1Adapter.wrap, (amount))});
    }

    function unwrap(address strategyAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({target: strategyAdapter, callData: abi.encodeCall(IwstETHV1Adapter.unwrap, (amount))});
    }
}
