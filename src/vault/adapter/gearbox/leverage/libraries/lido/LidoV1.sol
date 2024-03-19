// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2023
pragma solidity ^0.8.17;

import {ILidoV1Adapter} from "../../../interfaces/lido/ILidoV1Adapter.sol";

library LidoV1 {
    function submit(address protocolAdapter, uint256 amount) internal pure returns (MultiCall memory) {
        return MultiCall({target: protocolAdapter, callData: abi.encodeCall(ILidoV1Adapter.submit, (amount))});
    }
}
