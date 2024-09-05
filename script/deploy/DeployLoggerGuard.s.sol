// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {LoggerGuard} from "../../src/peripheral/gnosis/LoggerGuard.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        new LoggerGuard();

        vm.stopBroadcast();
    }
}
