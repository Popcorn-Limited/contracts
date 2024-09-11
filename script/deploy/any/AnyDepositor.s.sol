// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AnyDepositor, IERC20} from "src/strategies/AnyDepositor.sol";

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (AnyDepositor strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/any/AnyDepositorDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        strategy = new AnyDepositor();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(
                json.readAddress(".strategyInit.yieldAsset"),
                json.readAddress(".strategyInit.oracle"),
                json.readUint(".strategyInit.slippage"),
                json.readUint(".strategyInit.floatRatio")
            )
        );

        vm.stopBroadcast();
    }
}
