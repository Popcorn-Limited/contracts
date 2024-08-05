// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyConverter} from "src/strategies/AnyConverter.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, IERC20} from "../BaseStrategyTest.sol";
import {MockOracle} from "test/utils/mocks/MockOracle.sol";
import "forge-std/console.sol";

abstract contract AnyBaseTest is BaseStrategyTest {
    using stdJson for string;

    address yieldAsset;
    MockOracle oracle;

    function _increasePricePerShare(uint256 amount) internal override {
        deal(testConfig.asset, yieldAsset, IERC20(testConfig.asset).balanceOf(yieldAsset) + amount);
    }

    function _prepareConversion(address token, uint256 amount) internal {
        if (token == yieldAsset) {
            vm.prank(json.readAddress(string.concat(".configs[0].specific.whale")));
            IERC20(token).transfer(address(this), amount);
        } else {
            deal(token, address(this), amount);
        }

        IERC20(token).approve(address(strategy), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            AUTODEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @dev Partially withdraw assets directly from strategy and the underlying protocol
    function test__withdraw_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 pushAmount = (testConfig.defaultAmount / 5) * 2;

        console.log("pushAmount", pushAmount);
        console.log("defaultAmount", testConfig.defaultAmount);

        _prepareConversion(yieldAsset, pushAmount);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds(pushAmount, bytes(""));

        // Withdraw 80% of deposit
        vm.prank(bob);
        strategy.withdraw((testConfig.defaultAmount / 5) * 4, bob, bob);

        console.log("withdraw", (testConfig.defaultAmount / 5) * 4);

        console.log("asset bal", IERC20(testConfig.asset).balanceOf(address(strategy)));
        console.log("yieldAsset bal", IERC20(yieldAsset).balanceOf(address(strategy)));
        console.log("reserved assets", AnyConverter(address(strategy)).totalReservedAssets());
        console.log("reserved yieldAssets", AnyConverter(address(strategy)).totalReservedYieldAssets());
        console.log("total assets", strategy.totalAssets());

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, _delta_, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, _delta_, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, _delta_, "asset bal");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount / 5, _delta_, "strategy asset bal"
        );
    }

    /// @dev Partially redeem assets directly from strategy and the underlying protocol
    function test__redeem_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 pushAmount = (testConfig.defaultAmount / 5) * 2;
        _prepareConversion(yieldAsset, pushAmount);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds(pushAmount, bytes(""));

        // Redeem 80% of deposit
        vm.prank(bob);
        strategy.redeem((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, _delta_, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, _delta_, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, _delta_, "asset bal");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount / 5, _delta_, "strategy asset bal"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PUSH/PULL FUNDS
    //////////////////////////////////////////////////////////////*/

    function test__pushFunds() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        _prepareConversion(yieldAsset, testConfig.defaultAmount);

        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        uint256 reserved = AnyConverter(address(strategy)).totalReservedAssets();

        assertEq(IERC20(yieldAsset).balanceOf(address(strategy)), testConfig.defaultAmount);
        assertEq(IERC20(testConfig.asset).balanceOf(address(strategy)) - reserved, 0);
        assertEq(reserved, testConfig.defaultAmount);

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)) - reserved, 0, _delta_, "strategy asset bal");
    }

    function test__pullFunds() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _prepareConversion(yieldAsset, testConfig.defaultAmount);
        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        _prepareConversion(testConfig.asset, testConfig.defaultAmount);
        strategy.pullFunds(testConfig.defaultAmount, bytes(""));

        uint256 reservedAssets = AnyConverter(address(strategy)).totalReservedAssets();
        uint256 reservedYieldAsset = AnyConverter(address(strategy)).totalReservedYieldAssets();

        assertEq(IERC20(yieldAsset).balanceOf(address(strategy)) - reservedYieldAsset, 0);
        assertEq(IERC20(testConfig.asset).balanceOf(address(strategy)) - reservedAssets, testConfig.defaultAmount);

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)) - reservedAssets,
            testConfig.defaultAmount,
            _delta_,
            "strategy asset bal"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM RESERVES
    //////////////////////////////////////////////////////////////*/

    function test__should_use_old_favorable_quote() public {
        // price of asset went up after the keeper reserved the funds
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _prepareConversion(yieldAsset, testConfig.defaultAmount);
        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        oracle.setPrice(_asset_, yieldAsset, testConfig.defaultAmount * 11_000 / 10_000);

        uint256 ta = strategy.totalAssets();

        // claim needs to be unlocked
        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number);

        // while the user had 1e18 of asset reserved, they are only able to withdraw
        // 9e17 of it. Thus, 1e17 is left in the contract and added to the total assets
        // after the claim. Thus, total assets increases
        assertGt(strategy.totalAssets(), ta, "total assets should increase because of the new favorable quote");
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            testConfig.defaultAmount,
            "should receive assets with old favorable quote"
        );
    }

    function test__should_use_new_favorable_quote() public {
        // price of asset went down after the keeper reserved the funds
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _prepareConversion(yieldAsset, testConfig.defaultAmount);
        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        oracle.setPrice(_asset_, yieldAsset, testConfig.defaultAmount * 9_000 / 10_000);
        // oracle.setPrice(yieldAsset, _asset_, testConfig.defaultAmount * 11_000 / 10_000);

        uint256 ta = strategy.totalAssets();

        // claim needs to be unlocked
        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number);

        assertGt(strategy.totalAssets(), ta, "total assets should increase because of the new favorable quote");
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            testConfig.defaultAmount * 9_000 / 10_000,
            "should receive assets with old favorable quote"
        );
    }

    function test__should_use_old_favorable_quote_with_multiple_reserves() public {
        strategy.toggleAutoDeposit();
        uint256 amount = 1e18;
        _mintAssetAndApproveForStrategy(amount * 3, bob);
        vm.prank(bob);
        strategy.deposit(amount * 3, bob);

        // the keeper will push the funds three times
        // Each time they push the price will have changed. We'll check whether the
        // correct prices are used for the claiming of the keeper's reserves

        _prepareConversion(yieldAsset, amount * 3);
        strategy.pushFunds(amount, bytes(""));

        // price increase by 10%
        vm.roll(block.number + 1);
        oracle.setPrice(yieldAsset, _asset_, amount * 11_000 / 10_000);
        console.log("total assets before second push", strategy.totalAssets());
        console.log("reserved assets before second push", AnyConverter(address(strategy)).totalReservedAssets());
        strategy.pushFunds(1e18, bytes(""));
        console.log("total assets after second push", strategy.totalAssets());
        console.log("reserved assets after second push", AnyConverter(address(strategy)).totalReservedAssets());

        // price decrease by 20%
        vm.roll(block.number + 1);
        oracle.setPrice(yieldAsset, _asset_, amount * 10_500 / 10_000);
        console.log("total assets before third push", strategy.totalAssets());
        strategy.pushFunds(1e18, bytes(""));
        console.log("total assets after third push", strategy.totalAssets());
    }
}
