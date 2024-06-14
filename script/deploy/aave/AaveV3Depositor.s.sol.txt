// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AaveV3Depositor, IERC20} from "../../../src/strategies/aave/aaveV3/AaveV3Depositor.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/aave/AaveV3DepositorDeployConfig.json"
            )
        );

        AaveV3Depositor strategy = new AaveV3Depositor();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(json.readAddress(".strategyInit.aaveDataProvider"))
        );
    }
}
