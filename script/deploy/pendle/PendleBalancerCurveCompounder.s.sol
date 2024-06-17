// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IPendleRouter, IPendleSYToken, ISYTokenV3} from "src/strategies/pendle/IPendle.sol";
import {PendleBalancerCurveCompounder, CurveSwap, IERC20, PendleDepositor} from "src/strategies/pendle/PendleBalancerCurveCompounder.sol";
import {TradePath, IAsset, BatchSwapStep} from "src/peripheral/BaseBalancerCompounder.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public {
        string memory json = vm.readFile(
            string.concat(
                vm.projectRoot(),
                "./script/deploy/pendle/PendleBalancerCurveCompounderDeployConfig.json"
            )
        );

        // Deploy strategy
        PendleBalancerCurveCompounder strategy = new PendleBalancerCurveCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoHarvest"),
            abi.encode(
                json.readAddress(".strategyInit.pendleMarket"),
                json.readAddress(".strategyInit.pendleRouter"),
                json.readAddress(".strategyInit.pendleRouterStat")
            )
        );

        _setHarvestValues(json, payable(address(strategy)));
    }

    function _setHarvestValues(
        string memory json,
        address payable strategy
    ) internal {
        // Read harvest values
        address balancerVault_ = json.readAddress(".harvest.balancerVault");

        TradePath[] memory tradePaths_ = _getTradePaths(json);

        address curveRouter_ = json.readAddress(".harvest.curveRouter");

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json);

        // Set harvest values
        PendleBalancerCurveCompounder(strategy).setHarvestValues(
            balancerVault_,
            tradePaths_,
            curveRouter_,
            swaps_
        );
    }

    function _getTradePaths(
        string memory json
    ) internal pure returns (TradePath[] memory) {
        uint256 swapLen = json.readUint(".harvest.tradePaths.length");

        TradePath[] memory tradePaths_ = new TradePath[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory assetAddresses = json.readAddressArray(
                string.concat(
                    ".harvest.tradePaths.structs[",
                    vm.toString(i),
                    "].assets"
                )
            );
            IAsset[] memory assets = new IAsset[](assetAddresses.length);
            for (uint256 n; n < assetAddresses.length; n++) {
                assets[n] = IAsset(assetAddresses[n]);
            }

            int256[] memory limits = json.readIntArray(
                string.concat(
                    ".harvest.tradePaths.structs[",
                    vm.toString(i),
                    "].limits"
                )
            );

            BatchSwapStep[] memory swapSteps = abi.decode(
                json.parseRaw(
                    string.concat(
                        ".harvest.tradePaths.structs[",
                        vm.toString(i),
                        "].swaps"
                    )
                ),
                (BatchSwapStep[])
            );

            tradePaths_[i] = TradePath({
                assets: assets,
                limits: limits,
                swaps: abi.encode(swapSteps)
            });
        }

        return tradePaths_;
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
