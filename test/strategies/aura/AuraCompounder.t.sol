// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AuraCompounder, HarvestValues, TradePath} from "../../../src/strategies/aura/AuraCompounder.sol";
import {IAsset, BatchSwapStep} from "../../../src/interfaces/external/balancer/IBalancerVault.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

contract AuraCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/aura/AuraCompounderTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        address booster = json_.readAddress(string.concat(".configs[", index_, "].specific.init.auraBooster"));

        uint256 pid = json_.readUint(string.concat(".configs[", index_, "].specific.init.auraPoolId"));

        // Deploy Strategy
        AuraCompounder strategy = new AuraCompounder();

        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(booster, pid));

        // Set Harvest values
        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function _setHarvestValues(string memory json_, string memory index_, address strategy) internal {
        // Read harvest values
        address balancerVault_ =
            json_.readAddress(string.concat(".configs[", index_, "].specific.harvest.balancerVault"));

        HarvestValues memory harvestValues_ = abi.decode(
            json_.parseRaw(string.concat(".configs[", index_, "].specific.harvest.harvestValues")), (HarvestValues)
        );

        TradePath[] memory tradePaths_ = _getTradePaths(json_, index_);

        // Set harvest values
        AuraCompounder(strategy).setHarvestValues(balancerVault_, tradePaths_, harvestValues_);
    }

    function _getTradePaths(string memory json_, string memory index_) internal pure returns (TradePath[] memory) {
        uint256 swapLen = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.tradePaths.length"));

        TradePath[] memory tradePaths_ = new TradePath[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory assetAddresses = json_.readAddressArray(
                string.concat(".configs[", index_, "].specific.harvest.tradePaths.structs[", vm.toString(i), "].assets")
            );
            IAsset[] memory assets = new IAsset[](assetAddresses.length);
            for (uint256 n; n < assetAddresses.length; n++) {
                assets[n] = IAsset(assetAddresses[n]);
            }

            int256[] memory limits = json_.readIntArray(
                string.concat(".configs[", index_, "].specific.harvest.tradePaths.structs[", vm.toString(i), "].limits")
            );

            BatchSwapStep[] memory swapSteps = abi.decode(
                json_.parseRaw(
                    string.concat(
                        ".configs[", index_, "].specific.harvest.tradePaths.structs[", vm.toString(i), "].swaps"
                    )
                ),
                (BatchSwapStep[])
            );

            tradePaths_[i] = TradePath({assets: assets, limits: limits, swaps: abi.encode(swapSteps)});
        }

        return tradePaths_;
    }

    function _increasePricePerShare(uint256 amount) internal override {
        // address aToken = address(AaveV3Depositor(address(strategy)).aToken());
        // deal(
        //     testConfig.asset,
        //     aToken,
        //     IERC20(testConfig.asset).balanceOf(aToken) + amount
        // );
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        strategy.harvest(abi.encode(uint256(0)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_slippage_too_high() public {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        strategy.harvest(abi.encode(uint256(1e18)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_no_rewards() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        strategy.harvest(abi.encode(uint256(1e18)));

        assertEq(strategy.totalAssets(), oldTa);
    }
}
