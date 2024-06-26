// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BalancerSingleAssetCompounder, IERC20, TradePath, InitValues} from "src/strategies/balancer/BalancerSingleAssetCompounder.sol";
import {IAsset, BatchSwapStep} from "src/interfaces/external/balancer/IBalancer.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import "forge-std/console.sol";

contract BalancerSingleAssetCompounderTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/balancer/BalancerSingleAssetConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        address minter = json_.readAddress(string.concat(".configs[", index_, "].specific.init.minter"));
        address gauge = json_.readAddress(string.concat(".configs[", index_, "].specific.init.gauge"));
        address vault = json_.readAddress(string.concat(".configs[", index_, "].specific.init.vault"));
        uint256 index = json_.readUint(string.concat(".configs[", index_, "].specific.init.assetIndex"));
        uint256 userDataIndex = json_.readUint(string.concat(".configs[", index_, "].specific.init.indexInUserData"));
        uint256 amountsInLen = json_.readUint(string.concat(".configs[", index_, "].specific.init.amountsInLen"));

        bytes32 poolId = json_.readBytes32(string.concat(".configs[", index_, "].specific.init.poolId"));

        // Deploy Strategy
        BalancerSingleAssetCompounder strategy = new BalancerSingleAssetCompounder();

        InitValues memory values = InitValues(
            minter, 
            gauge, 
            vault, 
            index, 
            userDataIndex, 
            amountsInLen, 
            poolId
        );

        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(values));

        // Set Harvest values
        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function _setHarvestValues(string memory json_, string memory index_, address strategy) internal {
        // Read harvest values
        address balancerVault_ =
            json_.readAddress(string.concat(".configs[", index_, "].specific.harvest.balancerVault"));

        TradePath[] memory tradePaths_ = _getTradePaths(json_, index_);

        // Set harvest values
        BalancerSingleAssetCompounder(strategy).setHarvestValues(balancerVault_, tradePaths_);
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

    // function _increasePricePerShare(uint256 amount) internal override {
    //     address aToken = address(AaveV3Depositor(address(strategy)).aToken());
    //     deal(
    //         testConfig.asset,
    //         aToken,
    //         IERC20(testConfig.asset).balanceOf(aToken) + amount
    //     );
    // }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    // function test_deposit1() public {
    //     _mintAssetAndApproveForStrategy(1e18, bob);
    //     vm.prank(bob);
    //     strategy.deposit(1e18, bob);

    //     // deal(address(0x596192bB6e41802428Ac943D2f1476C1Af25CC0E), address(strategy), 1e18);
    //     // console.log(strategy.totalAssets());

    //     uint256 am = strategy.totalAssets();
    //     console.log("OUT", am, bob);
    //     vm.prank(bob);
    //     console.log("WITH 1");
    //     strategy.withdraw(am.mulDiv(1e18, 2e18, Math.Rounding.Floor), bob, bob);
    //     console.log("BAL", IERC20(strategy.asset()).balanceOf(address(strategy)));
        
    //     am = strategy.totalAssets();
    //     console.log("WITHDRAWING 2", am);
        
    //     vm.prank(bob);
    //     strategy.withdraw(am, bob, bob);

    //     console.log("LOL", IERC20(strategy.asset()).balanceOf(address(strategy)), strategy.totalAssets());
    // }

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
