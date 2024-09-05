// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {AuraCompounder, HarvestValues, TradePath} from "src/strategies/aura/AuraCompounder.sol";
import {IAsset, BatchSwapStep} from "src/interfaces/external/balancer/IBalancer.sol";

contract Deploy is Script {
    using stdJson for string;

    function run() public returns (AuraCompounder strategy) {
        string memory json =
            vm.readFile(string.concat(vm.projectRoot(), "/script/deploy/aura/AuraCompounderDeployConfig.json"));

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy Strategy
        strategy = new AuraCompounder();

        strategy.initialize(
            json.readAddress(".baseInit.asset"),
            json.readAddress(".baseInit.owner"),
            json.readBool(".baseInit.autoDeposit"),
            abi.encode(json.readAddress(".strategyInit.auraBooster"), json.readUint(".strategyInit.auraPoolId"))
        );

        _setHarvestValues(json, address(strategy));

        vm.stopBroadcast();
    }

    function _setHarvestValues(string memory json, address strategy) internal {
        // Read harvest values
        address balancerVault_ = json.readAddress(".harvest.balancerVault");

        TradePath[] memory tradePaths_ = _getTradePaths(json);

        HarvestValues memory harvestValues_ = abi.decode(json.parseRaw(".harvest.harvestValues"), (HarvestValues));

        // Set harvest values
        AuraCompounder(strategy).setHarvestValues(balancerVault_, tradePaths_, harvestValues_);
    }

    function _getTradePaths(string memory json) internal pure returns (TradePath[] memory) {
        uint256 swapLen = json.readUint(".harvest.tradePaths.length");

        TradePath[] memory tradePaths_ = new TradePath[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory assetAddresses =
                json.readAddressArray(string.concat(".harvest.tradePaths.structs[", vm.toString(i), "].assets"));
            IAsset[] memory assets = new IAsset[](assetAddresses.length);
            for (uint256 n; n < assetAddresses.length; n++) {
                assets[n] = IAsset(assetAddresses[n]);
            }

            int256[] memory limits =
                json.readIntArray(string.concat(".harvest.tradePaths.structs[", vm.toString(i), "].limits"));

            BatchSwapStep[] memory swapSteps = abi.decode(
                json.parseRaw(string.concat(".harvest.tradePaths.structs[", vm.toString(i), "].swaps")),
                (BatchSwapStep[])
            );

            tradePaths_[i] = TradePath({assets: assets, limits: limits, swaps: abi.encode(swapSteps)});
        }

        return tradePaths_;
    }
}
