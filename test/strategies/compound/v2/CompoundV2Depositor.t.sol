// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {CompoundV2Depositor, IERC20} from "../../../../src/strategies/compound/v2/CompoundV2Depositor.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../../BaseStrategyTest.sol";

contract CompoundV2DepositorTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/compound/v2/CompoundV2DepositorTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        CompoundV2Depositor strategy = new CompoundV2Depositor();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(
                json_.readAddress(string.concat(".configs[", index_, "].specific.cToken")),
                json_.readAddress(string.concat(".configs[", index_, "].specific.comptroller"))
            )
        );

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256 amount) internal override {
        address cToken = address(CompoundV2Depositor(address(strategy)).cToken());
        deal(testConfig.asset, cToken, IERC20(testConfig.asset).balanceOf(cToken) + amount);
    }

    /*//////////////////////////////////////////////////////////////
                            OVERRIDEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        /// Some strategies have slippage or rounding errors which makes `maWithdraw` lower than the deposit amount
        uint256 reqAssets = ((strategy.previewMint(strategy.previewWithdraw(amount))) * 11) / 10;

        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        prop_previewWithdraw(bob, bob, bob, amount, testConfig.testId);
    }

    function test__withdraw_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds((testConfig.defaultAmount / 5) * 2, bytes(""));

        // Withdraw 80% of deposit
        vm.prank(bob);
        strategy.withdraw((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, 95491862, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, 29141911, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, 29141911, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, _delta_, "asset bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    /// @dev Partially redeem assets directly from strategy and the underlying protocol
    function test__redeem_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds((testConfig.defaultAmount / 5) * 2, bytes(""));

        // Redeem 80% of deposit
        vm.prank(bob);
        strategy.redeem((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, 192304855, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, _delta_, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, _delta_, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, 29141911, "asset bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    function test__pushFunds() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        assertApproxEqAbs(strategy.totalAssets(), oldTa, 204774025, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    function test__pullFunds() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        strategy.pullFunds(testConfig.defaultAmount, bytes(""));

        assertApproxEqAbs(strategy.totalAssets(), oldTa, 204774025, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount, _delta_, "strategy asset bal"
        );
    }

    // @dev Slippage on unpausing is higher than the delta for all other interactions
    function test__unpause() public override {
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount * 3, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount * 3, bob);

        uint256 oldTotalAssets = strategy.totalAssets();

        vm.prank(address(this));
        strategy.pause();

        vm.prank(address(this));
        strategy.unpause();

        // We simply deposit back into the external protocol
        // TotalAssets shouldnt change significantly besides some slippage or rounding errors
        assertApproxEqAbs(oldTotalAssets, strategy.totalAssets(), 1e8 * 3, "totalAssets");
        assertApproxEqAbs(IERC20(testConfig.asset).balanceOf(address(strategy)), 0, testConfig.delta, "asset balance");
    }
}
