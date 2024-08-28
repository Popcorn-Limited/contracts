// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {CompoundV2Depositor, IERC20} from "src/strategies/compound/v2/CompoundV2Depositor.sol";

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (CompoundV2Depositor strategy) {
        string memory json = vm.readFile(
            string.concat(vm.projectRoot(), "/script/deploy/compound/v2/CompoundV2DepositorDeployConfig.json")
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        strategy = new CompoundV2Depositor();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(json.readAddress(".strategyInit.cToken"), json.readAddress(".strategyInit.comptroller"))
        );

        vm.stopBroadcast();
    }
}
