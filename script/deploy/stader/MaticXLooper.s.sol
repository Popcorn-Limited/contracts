// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {MaticXLooper, LooperInitValues, IERC20} from "../../../src/strategies/stader/MaticXLooper.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (MaticXLooper strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/stader/MaticXLooperDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy Strategy
        strategy = new MaticXLooper();

        LooperInitValues memory looperValues = abi.decode(
            json.parseRaw(".strategyInit"),
            (LooperInitValues)
        );

        address asset = json.readAddress(".baseInit.asset");

        strategy.initialize(
            asset,
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(
                looperValues.aaveDataProvider,
                looperValues.balancerVault,
                looperValues.maticXPool,
                looperValues.maxLTV,
                looperValues.poolAddressesProvider,
                looperValues.poolId,
                looperValues.slippage,
                looperValues.targetLTV
            )
        );

        IERC20(asset).approve(address(strategy), 1);
        strategy.setUserUseReserveAsCollateral(1);

        vm.stopBroadcast();
    }
}
