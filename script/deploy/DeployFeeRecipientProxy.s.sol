// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {FeeRecipientProxy} from "src/utils/FeeRecipientProxy.sol";

contract Deploy is Script {
    function run() public returns (FeeRecipientProxy feeRecipient) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        feeRecipient = new FeeRecipientProxy{
            salt: bytes32("FeeRecipientProxy")
        }(msg.sender);

        vm.stopBroadcast();
    }
}
