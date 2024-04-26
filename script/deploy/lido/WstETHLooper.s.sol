// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {WstETHLooper, IERC20} from "../../../src/strategies/lido/WstETHLooper.sol";

struct LooperValues {
    address aaveDataProvider;
    uint256 maxLTV;
    address poolAddressProvider;
    uint256 slippage;
    uint256 targetLTV;
}

contract WstETHLooperTest is Script {
    using stdJson for string;

    IERC20 wstETH;
    IERC20 awstETH;
    IERC20 vdWETH;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/lido/WstETHLooperDeployConfig.json"
            )
        );

        LooperValues memory looperValues = abi.decode(
            json.parseRaw(".strategyInit"),
            (LooperValues)
        );

        // Deploy Strategy
        WstETHLooper strategy = new WstETHLooper();

        address asset = json.readAddress(".baseInit.asset");

        strategy.initialize(
            asset,
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(
                looperValues.poolAddressProvider,
                looperValues.aaveDataProvider,
                looperValues.slippage,
                looperValues.targetLTV,
                looperValues.maxLTV
            )
        );

        IERC20(asset).approve(address(strategy), 1);
        strategy.setUserUseReserveAsCollateral(1);
    }
}
