// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {sAVAXLooper, LooperValues, LooperBaseValues, IERC20} from "../../../src/strategies/benqi/sAvaxLooper.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (sAVAXLooper strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/benqi/sAVAXLooperDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy Strategy
        strategy = new sAVAXLooper();

        LooperBaseValues memory baseValues = abi.decode(
            json.parseRaw(".baseLeverage"),
            (LooperBaseValues)
        );

        LooperValues memory looperInitValues = abi.decode(
            json.parseRaw(".strategy"),
            (LooperValues)
        );

        address asset = json.readAddress(".baseInit.asset");

        strategy.initialize(
            asset,
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(
                baseValues,
                looperInitValues
            )
        );

        vm.stopBroadcast();
    }
}
