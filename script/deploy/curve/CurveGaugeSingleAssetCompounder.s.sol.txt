// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {CurveGaugeSingleAssetCompounder, IERC20, CurveSwap} from "../../../src/strategies/curve/gauge/other/CurveGaugeSingleAssetCompounder.sol";

struct CurveGaugeInit {
    address gauge;
    int128 indexIn;
    address lpToken;
}

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/curve/CurveGaugeSingleAssetCompounderDeployConfig.json"
            )
        );

        CurveGaugeInit memory curveInit = abi.decode(
            json.parseRaw(".strategyInit"),
            (CurveGaugeInit)
        );

        // Deploy Strategy
        CurveGaugeSingleAssetCompounder strategy = new CurveGaugeSingleAssetCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(curveInit.lpToken, curveInit.gauge, curveInit.indexIn)
        );

        address curveRouter_ = abi.decode(
            json.parseRaw(".harvest.curveRouter"),
            (address)
        );

        uint256 discountBps_ = abi.decode(
            json.parseRaw(".harvest.discountBps"),
            (uint256)
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
            discountBps_
        );
    }
}
