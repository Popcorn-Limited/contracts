// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BalancerCompounder, IERC20, BatchSwapStep, IAsset, BalancerValues, HarvestValues, HarvestTradePath, TradePath} from "../../../src/strategies/balancer/BalancerCompounder.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/balancer/BalancerCompounderDeployConfig.json"
            )
        );

        BalancerValues memory balancerValues_ = abi.decode(
            json.parseRaw(string.concat(".strategyInit")),
            (BalancerValues)
        );

        // Deploy Strategy
        BalancerCompounder strategy = new BalancerCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(balancerValues_)
        );

        HarvestValues memory harvestValues_ = abi.decode(
            json.parseRaw(".harvest.harvestValues"),
            (HarvestValues)
        );

        HarvestTradePath[] memory tradePaths_ = abi.decode(
            json.parseRaw(".harvest.tradePaths"),
            (HarvestTradePath[])
        );

        // Set harvest values
        strategy.setHarvestValues(harvestValues_, tradePaths_);
    }
}
