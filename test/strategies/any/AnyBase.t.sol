// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

import {AnyConverter} from "src/strategies/AnyConverter.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, IERC20} from "../BaseStrategyTest.sol";
import "forge-std/console.sol";

abstract contract AnyBaseTest is BaseStrategyTest {
    using stdJson for string;

    address yieldAsset;

    function _increasePricePerShare(uint256 amount) internal override {
        deal(
            testConfig.asset,
            yieldAsset,
            IERC20(testConfig.asset).balanceOf(yieldAsset) + amount
        );
    }

    function _prepareConversion(address token, uint256 amount) internal {
        if (token == yieldAsset) {
            vm.prank(
                json.readAddress(string.concat(".configs[0].specific.whale"))
            );
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

        console.log(
            "asset bal",
            IERC20(testConfig.asset).balanceOf(address(strategy))
        );
        console.log(
            "yieldAsset bal",
            IERC20(yieldAsset).balanceOf(address(strategy))
        );
        console.log(
            "reserved assets",
            AnyConverter(address(strategy)).totalReservedAssets()
        );
        console.log(
            "reserved yieldAssets",
            AnyConverter(address(strategy)).totalReservedYieldAssets()
        );
        console.log("total assets", strategy.totalAssets());

        assertApproxEqAbs(
            strategy.totalAssets(),
            testConfig.defaultAmount / 5,
            _delta_,
            "ta"
        );
        assertApproxEqAbs(
            strategy.totalSupply(),
            testConfig.defaultAmount / 5,
            _delta_,
            "ts"
        );
        assertApproxEqAbs(
            strategy.balanceOf(bob),
            testConfig.defaultAmount / 5,
            _delta_,
            "share bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(bob),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "asset bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)),
            0,
            _delta_,
            "strategy asset bal"
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

        assertApproxEqAbs(
            strategy.totalAssets(),
            testConfig.defaultAmount / 5,
            _delta_,
            "ta"
        );
        assertApproxEqAbs(
            strategy.totalSupply(),
            testConfig.defaultAmount / 5,
            _delta_,
            "ts"
        );
        assertApproxEqAbs(
            strategy.balanceOf(bob),
            testConfig.defaultAmount / 5,
            _delta_,
            "share bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(bob),
            (testConfig.defaultAmount / 5) * 4,
            _delta_,
            "asset bal"
        );
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)),
            0,
            _delta_,
            "strategy asset bal"
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

        uint256 reserved = AnyConverter(address(strategy))
            .totalReservedAssets();

        assertEq(
            IERC20(yieldAsset).balanceOf(address(strategy)),
            testConfig.defaultAmount
        );
        assertEq(
            IERC20(testConfig.asset).balanceOf(address(strategy)) - reserved,
            0
        );
        assertEq(reserved, testConfig.defaultAmount);

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)) - reserved,
            0,
            _delta_,
            "strategy asset bal"
        );
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

        uint256 reservedAssets = AnyConverter(address(strategy))
            .totalReservedAssets();
        uint256 reservedYieldAsset = AnyConverter(address(strategy))
            .totalReservedYieldAssets();

        assertEq(
            IERC20(yieldAsset).balanceOf(address(strategy)) -
                reservedYieldAsset,
            0
        );
        assertEq(
            IERC20(testConfig.asset).balanceOf(address(strategy)) -
                reservedAssets,
            testConfig.defaultAmount
        );

        assertApproxEqAbs(strategy.totalAssets(), oldTa, _delta_, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)) - reservedAssets,
            testConfig.defaultAmount,
            _delta_,
            "strategy asset bal"
        );
    }
}       