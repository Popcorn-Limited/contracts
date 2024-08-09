// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {PeapodsBalancerUniV2Compounder, SwapStep} from "src/strategies/peapods/PeapodsBalancerUniV2Compounder.sol";
import {BalancerCompounder, IERC20, HarvestValues, TradePath} from "src/strategies/balancer/BalancerCompounder.sol";
import {IAsset, BatchSwapStep} from "src/peripheral/BalancerTradeLibrary.sol";
import {IStakedToken} from "src/strategies/peapods/PeapodsStrategy.sol";

contract DeployStrategy is Script {
    using stdJson for string;

    function run() public returns (PeapodsBalancerUniV2Compounder strategy) {
        string memory json = vm.readFile(
            string.concat(vm.projectRoot(), "/script/deploy/peapods/PeapodsBalancerUniV2CompounderDeployConfig.json")
        );

        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // Deploy strategy
        strategy = new PeapodsBalancerUniV2Compounder();

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
        address uniswapRouter = json_.readAddress(".harvest.uniswap.uniswapRouter");

        // assets to buy with rewards and to add to liquidity
        address[] memory rewToken = new address[](1);
        rewToken[0] = json_.readAddress(".harvest.uniswap.rewTokens[0]");

        // set Uniswap trade paths
        SwapStep[] memory swaps = new SwapStep[](1);

        uint256 lenSwap0 = json_.readUint(".harvest.uniswap.tradePaths[0].length");

        address[] memory swap0 = new address[](lenSwap0); // PEAS - WETH
        for (uint256 i = 0; i < lenSwap0; i++) {
            swap0[i] = json_.readAddress(string.concat(".harvest.uniswap.tradePaths[0].path[", vm.toString(i), "]"));
        }

        swaps[0] = SwapStep(swap0);

        // BALANCER HARVEST VALUES
        address balancerVault_ = json_.readAddress(".harvest.balancer.balancerVault");

        HarvestValues memory harvestValues_ =
            abi.decode(json_.parseRaw(".harvest.balancer.harvestValues"), (HarvestValues));

        TradePath[] memory tradePaths_ = _getBalancerTradePaths(json_);

        PeapodsBalancerUniV2Compounder(strategy).setHarvestValues(
            balancerVault_, tradePaths_, harvestValues_, uniswapRouter, rewToken, swaps
        );
    }

    function _setBalancerHarvestValues(string memory json_, address strategy) internal {
        // Read harvest values
        address balancerVault_ = json_.readAddress(".harvest.balancer.balancerVault");

        HarvestValues memory harvestValues_ =
            abi.decode(json_.parseRaw(".harvest.balancer.harvestValues"), (HarvestValues));

        TradePath[] memory tradePaths_ = _getBalancerTradePaths(json_);

        // Set harvest values
        BalancerCompounder(strategy).setHarvestValues(balancerVault_, tradePaths_, harvestValues_);
    }

    function _getBalancerTradePaths(string memory json_) internal pure returns (TradePath[] memory) {
        uint256 swapLen = json_.readUint(string.concat(".harvest.balancer.tradePaths.length"));

        TradePath[] memory tradePaths_ = new TradePath[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory assetAddresses = json_.readAddressArray(
                string.concat(".harvest.balancer.tradePaths.structs[", vm.toString(i), "].assets")
            );
            IAsset[] memory assets = new IAsset[](assetAddresses.length);
            for (uint256 n; n < assetAddresses.length; n++) {
                assets[n] = IAsset(assetAddresses[n]);
            }

            int256[] memory limits =
                json_.readIntArray(string.concat(".harvest.balancer.tradePaths.structs[", vm.toString(i), "].limits"));

            BatchSwapStep[] memory swapSteps = abi.decode(
                json_.parseRaw(string.concat(".harvest.balancer.tradePaths.structs[", vm.toString(i), "].swaps")),
                (BatchSwapStep[])
            );

            tradePaths_[i] = TradePath({assets: assets, limits: limits, swaps: abi.encode(swapSteps)});
        }

        return tradePaths_;
    }
}
