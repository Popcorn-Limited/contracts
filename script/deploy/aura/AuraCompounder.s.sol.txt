// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AuraCompounder, IERC20, BatchSwapStep, IAsset, AuraValues, HarvestValues, HarvestTradePath, TradePath} from "../../../src/strategies/aura/AuraCompounder.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/aura/AuraCompounderDeployConfig.json"
            )
        );

        // Read strategy init values
        AuraValues memory auraValues_ = abi.decode(
            json.parseRaw(".strategyInit"),
            (AuraValues)
        );

        // Deploy Strategy
        AuraCompounder strategy = new AuraCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(auraValues_)
        );

        HarvestValues memory harvestValues_ = abi.decode(
            json.parseRaw(".harvest.harvestValues"),
            (HarvestValues)
        );

        HarvestTradePath[] memory tradePaths_ = abi.decode(
            json.parseRaw(".harvest.tradePaths"),
            (HarvestTradePath[])
        );

        strategy.setHarvestValues(harvestValues_, tradePaths_);
    }
}
