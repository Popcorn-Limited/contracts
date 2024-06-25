// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IonDepositor, SafeERC20, IERC20} from "src/strategies/ion/IonDepositor.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (IonDepositor strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/ion/IonDepositorDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy strategy
        strategy = new IonDepositor();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(json.readAddress(".strategyInit.ionPool"))
        );

        vm.stopBroadcast();
    }
}
