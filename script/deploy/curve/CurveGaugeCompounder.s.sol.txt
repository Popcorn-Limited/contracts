// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {CurveGaugeCompounder, IERC20, CurveSwap} from "../../../src/strategies/curve/gauge/mainnet/CurveGaugeCompounder.sol";

struct CurveGaugeInit {
    address gauge;
    address minter;
    address pool;
}

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./srcript/deploy/curve/CurveGaugeCompounderDeployConfig.json"
            )
        );

        CurveGaugeInit memory curveInit = abi.decode(
            json.parseRaw(".strategyInit"),
            (CurveGaugeInit)
        );

        // Deploy Strategy
        CurveGaugeCompounder strategy = new CurveGaugeCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(curveInit.gauge, curveInit.pool, curveInit.minter)
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
