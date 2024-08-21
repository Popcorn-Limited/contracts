// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {PushOracle} from "src/peripheral/oracles/adapter/pushOracle/PushOracle.sol";
import {PushOracleOwner} from "src/peripheral/oracles/adapter/pushOracle/PushOracleOwner.sol";

contract Deploy is Script {
    function run()
        public
        returns (PushOracle oracle, PushOracleOwner oracleOwner)
    {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        oracle = new PushOracle(msg.sender);
        oracleOwner = new PushOracleOwner(address(oracle), msg.sender);

        oracle.nominateNewOwner(address(oracleOwner));
        oracleOwner.acceptOracleOwnership();

        vm.stopBroadcast();
    }
}
