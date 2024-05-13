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

        // Set Harvest values
        _setHarvestValues(json, address(strategy));
    }

    function _setHarvestValues(string memory json_, address strategy) internal {
        // Read harvest values
        address curveRouter_ = abi.decode(
            json_.parseRaw(".harvest.curveRouter"),
            (address)
        );

        int128 indexIn_ = abi.decode(
            json_.parseRaw(".harvest.indexIn"),
            (int128)
        );

        uint256[] memory minTradeAmounts_ = abi.decode(
            json_.parseRaw(".harvest.minTradeAmounts"),
            (uint256[])
        );

        address[] memory rewardTokens_ = abi.decode(
            json_.parseRaw(".harvest.rewardTokens"),
            (address[])
        );

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json_);

        // Set harvest values
        ConvexCompounder(strategy).setHarvestValues(
            curveRouter_,
            rewardTokens_,
            minTradeAmounts_,
            swaps_,
            indexIn_
        );
    }

    function _getCurveSwaps(
        string memory json_
    ) internal returns (CurveSwap[] memory) {
        //Construct CurveSwap structs
        uint256 swapLen = json_.readUint(string.concat(".harvest.swaps.length"));

        CurveSwap[] memory swaps_ = new CurveSwap[](swapLen);
        for (uint i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory route_ = json_.readAddressArray(
                string.concat(
                    ".harvest.harvest.swaps.structs[",
                    vm.toString(i),
                    "].route"
                )
            );
            address[11] memory route;
            for (uint n; n < 11; n++) {
                route[n] = route_[n];
            }

            // Read swapParams and convert dynamic into fixed size array
            uint256[5][5] memory swapParams;
            for (uint n = 0; n < 5; n++) {
                uint256[] memory swapParams_ = json_.readUintArray(
                    string.concat(
                        "harvest.swaps.structs[",
                        vm.toString(i),
                        "].swapParams[",
                        vm.toString(n),
                        "]"
                    )
                );
                for (uint y; y < 5; y++) {
                    swapParams[n][y] = swapParams_[y];
                }
            }

            // Read pools and convert dynamic into fixed size array
            address[] memory pools_ = json_.readAddressArray(
                string.concat(
                    "harvest.swaps.structs[",
                    vm.toString(i),
                    "].pools"
                )
            );
            address[5] memory pools;
            for (uint n = 0; n < 5; n++) {
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
