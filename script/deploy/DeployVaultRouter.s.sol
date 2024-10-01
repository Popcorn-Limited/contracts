// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {VaultRouter} from "src/utils/VaultRouter.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        new VaultRouter{salt: bytes32("VaultRouter")}();

        vm.stopBroadcast();
    }
}
