// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AnyCompounder, IERC20} from "src/strategies/AnyCompounder.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (AnyCompounder strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/any/AnyCompounderDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        strategy = new AnyCompounder();

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

        strategy.setRewardTokens(
            json.readAddressArray(".strategyInit.rewardTokens")
        );

        vm.stopBroadcast();
    }
}
