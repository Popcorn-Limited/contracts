// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {GearboxLeverageFarmWstETHV1} from "../../../../src/strategies/gearbox/leverageFarm/lido/GearboxLeverageFarmWstETHV1.sol";
import {ILeverageAdapter} from "../../../../src/strategies/gearbox/leverageFarm/IGearboxV3.sol";

struct GearboxValues {
    address creditFacade;
    address creditManager;
    address strategyAdapter;
}

contract GearboxLeverageFarmWstETHTest is Script {
    using stdJson for string;
    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/gearbox/leverageFarm/GearboxLeverageDeployConfig.json"
            )
        );

        GearboxLeverageFarmWstETHV1 strategy = new GearboxLeverageFarmWstETHV1();

        // Read strategy init values
        GearboxValues memory gearboxValues = abi.decode(
                        json.parseRaw(".strategyInit"),

            (GearboxValues)
        );

        strategy.initialize(
             json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(
                gearboxValues.creditFacade,
                gearboxValues.creditManager,
                gearboxValues.strategyAdapter
            )
        );

    }
}
