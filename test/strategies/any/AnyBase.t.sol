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
        deal(
            testConfig.asset,
            yieldAsset,
            IERC20(testConfig.asset).balanceOf(yieldAsset) + amount
        );
    }

    function _mintYieldAsset(
        uint256 amount,
        address receiver
    ) internal virtual {
        vm.prank(json.readAddress(string.concat(".configs[0].specific.whale")));
        IERC20(yieldAsset).transfer(receiver, amount);

        vm.prank(receiver);
        IERC20(yieldAsset).approve(address(strategy), amount);
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

        _mintYieldAsset(pushAmount, address(this));

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
            testConfig.defaultAmount / 5,
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
        _mintYieldAsset(pushAmount, address(this));

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
            testConfig.defaultAmount / 5,
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

        _mintYieldAsset(testConfig.defaultAmount, address(this));

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

        _mintYieldAsset(testConfig.defaultAmount, address(this));
        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        _mintAsset(testConfig.defaultAmount, address(this));
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

    /*//////////////////////////////////////////////////////////////
                            CLAIM RESERVES
    //////////////////////////////////////////////////////////////*/

    function test__should_use_old_favorable_quote() public {
        // price of asset went up after the keeper reserved the funds
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        _mintYieldAsset(testConfig.defaultAmount, address(this));
        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        oracle.setPrice(yieldAsset, _asset_, (1e18 * 12_500) / 10_000);

        uint256 ta = strategy.totalAssets();

        // claim needs to be unlocked
        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number);

        assertGt(
            strategy.totalAssets(),
            ta,
            "total assets should increase because of the old favorable quote"
        );
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

        _mintYieldAsset(testConfig.defaultAmount, address(this));
        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        oracle.setPrice(yieldAsset, _asset_, (1e18 * 9_000) / 10_000);

        uint256 ta = strategy.totalAssets();

        // claim needs to be unlocked
        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number);

        // while the user had 1e18 of asset reserved, they are only able to withdraw
        // 9e17 of it. Thus, 1e17 is left in the contract and added to the total assets
        // after the claim. Thus, total assets increases
        assertGt(
            strategy.totalAssets(),
            ta,
            "total assets should increase because of the new favorable quote"
        );
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            (testConfig.defaultAmount * 9_000) / 10_000,
            "should receive assets with new favorable quote"
        );
    }

    function test__should_use_old_favorable_quote_with_multiple_reserves()
        public
    {
        strategy.toggleAutoDeposit();
        // changing amount will break the assertions
        uint256 amount = 1e18;
        _mintAssetAndApproveForStrategy(amount * 5, bob);
        vm.prank(bob);
        strategy.deposit(amount * 5, bob);

        // the keeper will push the funds three times
        // Each time they push the price will have changed. We'll check whether the
        // correct prices are used for the claiming of the keeper's reserves

        _mintYieldAsset(amount * 3, address(this));
        strategy.pushFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(yieldAsset, _asset_, (1e18 * 12_500) / 10_000);
        strategy.pushFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(yieldAsset, _asset_, (1e18 * 16_000) / 10_000);
        strategy.pushFunds(amount, bytes(""));

        vm.warp(block.timestamp + 2 days);

        // at the time this claim was reserved the ratio was 1:1
        AnyConverter(address(strategy)).claimReserved(block.number - 2);
        // 1.25:1 in favor of the yield asset
        AnyConverter(address(strategy)).claimReserved(block.number - 1);
        // 1.6:1 in favor of the yield asset
        AnyConverter(address(strategy)).claimReserved(block.number);

        // so we need to receive
        // 1. 1e18 * 1e18 / 1e18 = 1e18 asset
        // 2. 1e18 * 1.25e18 / 1e18 = 1.25e18 asset
        // 3. 1e18 * 1.6e18 / 1e18 = 1.6e18 asset
        // so in total we need to receive 1e18 + 1.25e18 + 1.6e18 = 3.85e18 asset

        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            3.85e18,
            "asset balance not correct"
        );
    }

    function test__should_use_new_favorable_quote_with_multiple_reserves()
        public
    {
        strategy.toggleAutoDeposit();
        // changing amount will break the assertions
        uint256 amount = 1e18;
        _mintAssetAndApproveForStrategy(amount * 3, bob);
        vm.prank(bob);
        strategy.deposit(amount * 3, bob);

        // the keeper will push the funds three times
        // Each time they push the price will have changed. We'll check whether the
        // correct prices are used for the claiming of the keeper's reserves

        _mintYieldAsset(amount * 3, address(this));
        strategy.pushFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(yieldAsset, _asset_, (1e18 * 7_500) / 10_000);
        strategy.pushFunds(1e18, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(yieldAsset, _asset_, (1e18 * 4_000) / 10_000);
        strategy.pushFunds(1e18, bytes(""));

        vm.warp(block.timestamp + 2 days);

        // at the time this claim was reserved the ratio was 1:1
        AnyConverter(address(strategy)).claimReserved(block.number - 2);
        // 0.75:1 in favor of the asset
        AnyConverter(address(strategy)).claimReserved(block.number - 1);
        // 0.4:1 in favor of the asset
        AnyConverter(address(strategy)).claimReserved(block.number);

        // should use new favorable quote 0.4:1 in favor of asset so we need to receive
        // 1. 1e18 * 0.4e18 / 1e18 = 0.4e18 asset
        // 1. 1e18 * 0.4e18 / 1e18 = 0.4e18 asset
        // 1. 1e18 * 0.4e18 / 1e18 = 0.4e18 asset
        // so in total we need to receive 0.4e18 + 0.4e18 + 0.4e18 = 1.2e18

        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            1.2e18,
            "asset balance not correct"
        );
    }

    function test__pull_funds_should_use_old_favorable_quote() public {
        _mintAsset(testConfig.defaultAmount, address(this));
        _mintYieldAsset(testConfig.defaultAmount * 2, address(this));
        // send yield assets to strategy. We'll pull them in this test
        IERC20(yieldAsset).transfer(
            address(strategy),
            testConfig.defaultAmount * 2
        );

        strategy.pullFunds(testConfig.defaultAmount, bytes(""));

        // price of asset went up after the keeper reserved the funds
        oracle.setPrice(_asset_, yieldAsset, (1e18 * 12_000) / 10_000);

        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number);

        // should use the old favorable quote 1:1 instead of 1.2:1 in favor of the asset

        assertEq(
            IERC20(yieldAsset).balanceOf(address(address(this))),
            1e18,
            "yield asset balance not correct"
        );
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            0,
            "asset balance not correct"
        );
    }

    function test__pull_funds_should_use_new_favorable_quote() public {
        _mintAsset(testConfig.defaultAmount, address(this));
        _mintYieldAsset(testConfig.defaultAmount * 2, address(this));
        // send yield assets to strategy. We'll pull them in this test
        IERC20(yieldAsset).transfer(
            address(strategy),
            testConfig.defaultAmount * 2
        );

        strategy.pullFunds(testConfig.defaultAmount, bytes(""));

        // price of asset went up after the keeper reserved the funds
        oracle.setPrice(_asset_, yieldAsset, (1e18 * 8_000) / 10_000);

        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number);

        // should use the old favorable quote 1:1 instead of 1.2:1 in favor of the asset

        assertEq(
            IERC20(yieldAsset).balanceOf(address(address(this))),
            0.8e18,
            "yield asset balance not correct"
        );
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            0,
            "asset balance not correct"
        );
    }

    function test__pull_funds_should_use_old_favorable_quote_with_multiple_reserves()
        public
    {
        uint256 amount = 1e18;
        _mintAsset(amount * 3, address(this));
        _mintYieldAsset(amount * 4, address(this));
        // send yield assets to strategy. We'll pull them in this test
        IERC20(yieldAsset).transfer(address(strategy), amount * 4);

        strategy.pullFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(_asset_, yieldAsset, (1e18 * 12_500) / 10_000);
        strategy.pullFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(_asset_, yieldAsset, (1e18 * 16_000) / 10_000);
        strategy.pullFunds(amount, bytes(""));

        vm.warp(block.timestamp + 2 days);

        // ratio 1:1
        AnyConverter(address(strategy)).claimReserved(block.number - 2);
        // ratio 1.25:1 in favor of the asset
        AnyConverter(address(strategy)).claimReserved(block.number - 1);
        // ratio 1.6:1 in favor of the asset
        AnyConverter(address(strategy)).claimReserved(block.number);

        // so we need to receive
        // 1. 1e18 * 1e18 / 1e18 = 1e18 yield asset
        // 2. 1e18 * 1.25e18 / 1e18 = 1.25e18 yield asset
        // 3. 1e18 * 1.6e18 / 1e18 = 1.6e18 yield asset
        // so in total we need to receive 1e18 + 1.25e18 + 1.6e18 = 3.85e18 yield asset

        // can be off by 1 because of precision
        assertApproxEqAbs(
            IERC20(yieldAsset).balanceOf(address(address(this))),
            3.85e18,
            1,
            "yield asset balance not correct"
        );
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            0,
            "asset balance not correct"
        );
    }

    function test__pull_funds_should_use_new_favorable_quote_with_multiple_reserves()
        public
    {
        uint256 amount = 1e18;
        _mintAsset(amount * 3, address(this));
        _mintYieldAsset(amount * 4, address(this));
        // send yield assets to strategy. We'll pull them in this test
        IERC20(yieldAsset).transfer(address(strategy), amount * 4);

        strategy.pullFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(_asset_, yieldAsset, (1e18 * 7_500) / 10_000);
        strategy.pullFunds(amount, bytes(""));

        vm.roll(block.number + 1);
        oracle.setPrice(_asset_, yieldAsset, (1e18 * 4_000) / 10_000);
        strategy.pullFunds(amount, bytes(""));

        vm.warp(block.timestamp + 2 days);

        AnyConverter(address(strategy)).claimReserved(block.number - 2);
        AnyConverter(address(strategy)).claimReserved(block.number - 1);
        AnyConverter(address(strategy)).claimReserved(block.number);

        // should use new favorable quote 0.4:1 in favor of yield asset so we need to receive
        // 1. 1e18 * 0.4e18 / 1e18 = 0.4e18 yield asset
        // 2. 1e18 * 0.4e18 / 1e18 = 0.4e18 yield asset
        // 3. 1e18 * 0.4e18 / 1e18 = 0.4e18 yield asset
        // so in total we need to receive 0.4e18 + 0.4e18 + 0.4e18 = 1.2e18 yield asset

        // can be off by 1 because of precision
        assertEq(
            IERC20(yieldAsset).balanceOf(address(address(this))),
            1.2e18,
            "yield asset balance not correct"
        );
        assertEq(
            IERC20(_asset_).balanceOf(address(this)),
            0,
            "asset balance not correct"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            RESCUE TOKEN
    //////////////////////////////////////////////////////////////*/

    function test__rescueToken() public {
        IERC20 rescueToken = IERC20(
            json.readAddress(string.concat(".configs[0].specific.rescueToken"))
        );
        uint256 rescueAmount = 10e18;
        deal(address(rescueToken), bob, rescueAmount);

        vm.prank(bob);
        rescueToken.transfer(address(strategy), rescueAmount);

        AnyConverter(address(strategy)).rescueToken(address(rescueToken));

        assertEq(rescueToken.balanceOf(address(strategy)), 0);
        assertEq(rescueToken.balanceOf(address(this)), rescueAmount);
    }

    function testFail__rescueToken_non_owner() public {
        IERC20 rescueToken = IERC20(
            json.readAddress(string.concat(".configs[0].specific.rescueToken"))
        );
        uint256 rescueAmount = 10e18;
        deal(address(rescueToken), bob, rescueAmount);

        vm.prank(bob);
        rescueToken.transfer(address(strategy), rescueAmount);

        vm.prank(bob);
        AnyConverter(address(strategy)).rescueToken(address(rescueToken));
    }

    function testFail__rescueToken_token_is_in_tokens() public {
        vm.expectRevert(AnyConverter.Misconfigured.selector);
        AnyConverter(address(strategy)).rescueToken(testConfig.asset);
    }
}
