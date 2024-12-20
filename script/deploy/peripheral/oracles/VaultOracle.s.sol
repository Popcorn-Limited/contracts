// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {PushOracle} from "src/peripheral/oracles/adapter/pushOracle/PushOracle.sol";
import {OracleVaultController} from "src/peripheral/oracles/OracleVaultController.sol";


contract Deploy is Script {
    function run()
        public
        returns (PushOracle oracle, OracleVaultController controller)
    {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        oracle = new PushOracle(msg.sender);
        controller = new OracleVaultController(address(oracle), msg.sender);

        oracle.nominateNewOwner(address(controller));
        controller.acceptOracleOwnership();

        vm.stopBroadcast();
    }
}