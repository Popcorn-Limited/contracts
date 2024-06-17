// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IonDepositor, SafeERC20, IERC20} from "src/strategies/ion/IonDepositor.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json =
            vm.readFile(string.concat(vm.projectRoot(), "./script/deploy/ion/IonDepositorDeployConfig.json"));

        // Deploy strategy
        IonDepositor strategy = new IonDepositor();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(json.readAddress(".strategyInit.ionPool"))
        );
    }
}
