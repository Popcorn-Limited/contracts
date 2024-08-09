// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {PeapodsUniV2Compounder, SwapStep} from "src/strategies/peapods/PeapodsUniV2Compounder.sol";
import {IStakedToken} from "src/strategies/peapods/PeapodsStrategy.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (PeapodsUniV2Compounder strategy) {
        string memory json = vm.readFile(
            string.concat(vm.projectRoot(), "/script/deploy/peapods/PeapodsUniV2CompounderDeployConfig.json")
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy strategy
        strategy = new PeapodsUniV2Compounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(json.readAddress(".strategyInit.stakingContract"))
        );

        _setHarvestValues(json, address(strategy));

        vm.stopBroadcast();
    }

    function _setHarvestValues(string memory json_, address strategy) internal {
        address router = json_.readAddress(".harvest.uniswapRouter");

        // assets to buy with rewards and to add to liquidity
        address[2] memory depositAssets;
        depositAssets[0] = json_.readAddress(".harvest.depositAssets[0]");
        depositAssets[1] = json_.readAddress(".harvest.depositAssets[1]");

        // set Uniswap trade paths
        SwapStep[] memory swaps = new SwapStep[](2);

        uint256 lenSwap0 = json_.readUint(".harvest.tradePaths[0].length");
        address[] memory swap0 = new address[](lenSwap0); // PEAS - WETH - DAI - pDAI
        for (uint256 i = 0; i < lenSwap0; i++) {
            swap0[i] = json_.readAddress(string.concat(".harvest.tradePaths[0].path[", vm.toString(i), "]"));
        }

        uint256 lenSwap1 = json_.readUint(".harvest.tradePaths[1].length");
        address[] memory swap1 = new address[](lenSwap1); // PEAS - WETH - DAI
        for (uint256 i = 0; i < lenSwap1; i++) {
            swap1[i] = json_.readAddress(string.concat(".harvest.tradePaths[1].path[", vm.toString(i), "]"));
        }

        swaps[0] = SwapStep(swap0);
        swaps[1] = SwapStep(swap1);

        // rewards
        uint256 rewLen = json_.readUint(".harvest.rewards.length");
        address[] memory rewardTokens = new address[](rewLen);
        for (uint256 i = 0; i < rewLen; i++) {
            rewardTokens[i] = json_.readAddress(string.concat(".harvest.rewards.tokens[", vm.toString(i), "]"));
        }

        PeapodsUniV2Compounder(strategy).setHarvestValues(rewardTokens, router, depositAssets, swaps);
    }
}
