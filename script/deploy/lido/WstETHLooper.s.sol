// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {WstETHLooper, LooperInitValues, IERC20} from "../../../src/strategies/lido/WstETHLooper.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    IERC20 wstETH;
    IERC20 awstETH;
    IERC20 vdWETH;

    function run() public returns (WstETHLooper strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/lido/WstETHLooperDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy Strategy
        strategy = new WstETHLooper();

        LooperInitValues memory looperValues = abi.decode(
            json.parseRaw(".strategyInit"),
            (LooperInitValues)
        );

        address asset = json.readAddress(".baseInit.asset");

        strategy.initialize(
            asset,
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(
                looperValues.aaveDataProvider,
                looperValues.curvePool,
                looperValues.maxLTV,
                looperValues.poolAddressesProvider,
                looperValues.slippage,
                looperValues.targetLTV
            )
        );

        IERC20(asset).approve(address(strategy), 1);
        strategy.setUserUseReserveAsCollateral(1);

        vm.stopBroadcast();
    }
}
