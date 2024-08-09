// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {CurveGaugeCompounder, IERC20, CurveSwap} from "src/strategies/curve/CurveGaugeCompounder.sol";

struct CurveGaugeInit {
    address gauge;
    address minter;
    address pool;
}

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (CurveGaugeCompounder strategy) {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "/script/deploy/curve/CurveGaugeCompounderDeployConfig.json"
            )
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy Strategy
        strategy = new CurveGaugeCompounder();

        CurveGaugeInit memory curveInit = abi.decode(
            json.parseRaw(".strategyInit"),
            (CurveGaugeInit)
        );

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(curveInit.gauge, curveInit.pool, curveInit.minter)
        );

        // Set Harvest values
        _setHarvestValues(json, address(strategy));

        vm.stopBroadcast();
    }

    function _setHarvestValues(string memory json, address strategy) internal {
        // Read harvest values
        address curveRouter_ = json.readAddress(".harvest.curveRouter");

        int128 indexIn_ = abi.decode(
            json.parseRaw(".harvest.indexIn"),
            (int128)
        );

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json);

        // Set harvest values
        CurveGaugeCompounder(strategy).setHarvestValues(
            curveRouter_,
            swaps_,
            indexIn_
        );
    }

    function _getCurveSwaps(
        string memory json
    ) internal pure returns (CurveSwap[] memory) {
        uint256 swapLen = json.readUint(".harvest.swaps.length");

        CurveSwap[] memory swaps_ = new CurveSwap[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory route_ = json.readAddressArray(
                string.concat(
                    ".harvest.swaps.structs[",
                    vm.toString(i),
                    "].route"
                )
            );
            address[11] memory route;
            for (uint256 n; n < 11; n++) {
                route[n] = route_[n];
            }

            // Read swapParams and convert dynamic into fixed size array
            uint256[5][5] memory swapParams;
            for (uint256 n = 0; n < 5; n++) {
                uint256[] memory swapParams_ = json.readUintArray(
                    string.concat(
                        ".harvest.swaps.structs[",
                        vm.toString(i),
                        "].swapParams[",
                        vm.toString(n),
                        "]"
                    )
                );
                for (uint256 y; y < 5; y++) {
                    swapParams[n][y] = swapParams_[y];
                }
            }

            // Read pools and convert dynamic into fixed size array
            address[] memory pools_ = json.readAddressArray(
                string.concat(
                    ".harvest.swaps.structs[",
                    vm.toString(i),
                    "].pools"
                )
            );
            address[5] memory pools;
            for (uint256 n = 0; n < 5; n++) {
                pools[n] = pools_[n];
            }

            // Construct the struct
            swaps_[i] = CurveSwap({
                route: route,
                swapParams: swapParams,
                pools: pools
            });
        }
        return swaps_;
    }
}
