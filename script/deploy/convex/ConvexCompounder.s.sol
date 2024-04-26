// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ConvexCompounder, IERC20, CurveSwap} from "../../../src/strategies/convex/ConvexCompounder.sol";

struct ConvexInit {
    address convexBooster;
    address curvePool;
    uint256 pid;
}

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/convex/ConvexCompounderDeployConfig.json"
            )
        );

        ConvexInit memory convexInit = abi.decode(
            json.parseRaw(".strategyInit"),
            (ConvexInit)
        );

        // Deploy Strategy
        ConvexCompounder strategy = new ConvexCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(
                convexInit.convexBooster,
                convexInit.curvePool,
                convexInit.pid
            )
        );

        address curveRouter_ = abi.decode(
            json.parseRaw(".harvest.curveRouter"),
            (address)
        );

        int128 indexIn_ = abi.decode(
            json.parseRaw(".harvest.indexIn"),
            (int128)
        );

        uint256[] memory minTradeAmounts_ = abi.decode(
            json.parseRaw(".harvest.minTradeAmounts"),
            (uint256[])
        );

        address[] memory rewardTokens_ = abi.decode(
            json.parseRaw(".harvest.rewardTokens"),
            (address[])
        );

        CurveSwap[] memory swaps_ = abi.decode(
            json.parseRaw(".harvest.swaps"),
            (CurveSwap[])
        );

        // Set harvest values
        strategy.setHarvestValues(
            curveRouter_,
            rewardTokens_,
            minTradeAmounts_,
            swaps_,
            indexIn_
        );
    }
}
