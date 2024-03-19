// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.15;
import { MultiCall } from "../../IGearboxV3.sol";
import { ILidoV1Adapter } from "../IAdapter.sol";

library LidoV1 {
    function submit(address strategyAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({target: strategyAdapter, callData: abi.encodeCall(ILidoV1Adapter.submit, (amount))});
    }
}
