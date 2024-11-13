// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {OracleVaultController, Limit} from "src/peripheral/oracles/OracleVaultController.sol";

contract SetLimit is Script {
    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        OracleVaultController(0x9759573d033e09C9A224DFC429aa93E4BD677A6c)
            .setLimit(
                0xa5F5e90304758250764Ad26CbdD04b68D6Ce5d2a,
                Limit({jump: 1e17, drawdown: 1e17})
            );

        vm.stopBroadcast();
    }
}
