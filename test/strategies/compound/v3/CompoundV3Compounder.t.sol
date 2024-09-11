// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CompoundV3Compounder, IERC20} from "src/strategies/compound/v3/CompoundV3Compounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "test/strategies/BaseStrategyTest.sol";

contract CompoundV3CompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/compound/v3/CompoundV3CompounderTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        CompoundV3Compounder strategy = new CompoundV3Compounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(
                json_.readAddress(string.concat(".configs[", index_, "].specific.cToken")),
                json_.readAddress(string.concat(".configs[", index_, "].specific.rewarder")),
                json_.readAddress(string.concat(".configs[", index_, "].specific.rewardToken"))
            )
        );

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        address cToken = address(CompoundV3Compounder(address(strategy)).cToken());
        _mintAsset(IERC20(testConfig.asset).balanceOf(cToken) + amount, cToken);
    }

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(10000e6, bob);

        vm.prank(bob);
        strategy.deposit(10000e6, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        uint256 harvestAmount = 100e6;

        _mintAsset(harvestAmount, address(this));

        IERC20(testConfig.asset).approve(address(strategy), harvestAmount);

        strategy.harvest(abi.encode(harvestAmount));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_no_rewards() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        strategy.harvest(abi.encode(uint256(0)));

        assertEq(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_not_approved() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        uint256 harvestAmount = 100e6;

        _mintAsset(harvestAmount, address(this));

        strategy.harvest(abi.encode(harvestAmount));

        assertEq(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_non_owner() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        uint256 harvestAmount = 100e6;

        _mintAsset(harvestAmount, alice);

        vm.prank(alice);
        IERC20(testConfig.asset).approve(address(strategy), harvestAmount);

        vm.prank(alice);
        strategy.harvest(abi.encode(harvestAmount));

        assertGt(strategy.totalAssets(), oldTa);
    }
}
