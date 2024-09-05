// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {ControllerModule} from "../../src/peripheral/gnosis/ControllerModule.sol";

contract Deploy is Script {
    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        new ControllerModule(
            0x3C99dEa58119DE3962253aea656e61E5fBE21613,
            msg.sender
        );

        vm.stopBroadcast();
    }
}
