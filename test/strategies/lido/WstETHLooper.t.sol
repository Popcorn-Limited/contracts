// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {
    WstETHLooper,
    LooperInitValues,
    IERC20,
    IERC20Metadata,
    IwstETH,
    ILendingPool,
    Math
} from "../../../src/strategies/lido/WstETHLooper.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";

contract WstETHLooperTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IERC20 wstETH;
    IERC20 awstETH;
    IERC20 vdWETH;
    ILendingPool lendingPool;
    WstETHLooper strategyContract;

    uint256 defaultAmount;
    uint256 slippage;

    function setUp() public {
        _setUpBaseTest(1, "./test/strategies/lido/WstETHLooperTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        LooperInitValues memory looperInitValues =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.init")), (LooperInitValues));

        // Deploy Strategy
        WstETHLooper strategy = new WstETHLooper();

        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(looperInitValues));

        strategyContract = WstETHLooper(payable(strategy));

        wstETH = IERC20(testConfig_.asset);
        awstETH = strategyContract.interestToken();
        vdWETH = strategyContract.debtToken();
        lendingPool = strategyContract.lendingPool();
        defaultAmount = testConfig_.defaultAmount;
        slippage = strategyContract.slippage();

        deal(testConfig_.asset, address(this), 1);
        IERC20(testConfig_.asset).approve(address(strategy), 1);
        strategyContract.setUserUseReserveAsCollateral(1);

        return IBaseStrategy(address(strategy));
    }

    // Verify that totalAssets returns the expected amount
    function test__verify_totalAssets() public {
        // Make sure totalAssets isnt 0
        deal(address(wstETH), bob, defaultAmount);
        vm.startPrank(bob);
        wstETH.approve(address(strategy), defaultAmount);
        strategy.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            strategy.totalAssets(),
            strategy.convertToAssets(strategy.totalSupply()),
            _delta_,
            string.concat("totalSupply converted != totalAssets")
        );
    }

    function increasePricePerShare(uint256 amount) public {
        deal(address(wstETH), address(strategy), amount);
        vm.startPrank(address(strategy));
        lendingPool.supply(address(wstETH), amount, address(strategy), 0);
        vm.stopPrank();
    }

    function test__initialization() public override {
        LooperInitValues memory looperInitValues =
            abi.decode(json.parseRaw(string.concat(".configs[1].specific.init")), (LooperInitValues));

        // Deploy Strategy
        WstETHLooper strategy = new WstETHLooper();

        strategy.initialize(testConfig.asset, address(this), true, abi.encode(looperInitValues));

        verify_adapterInit();
    }

    function test__deposit(uint8 fuzzAmount) public override {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

            _mintAssetAndApproveForStrategy(amount, bob);

            prop_deposit(bob, bob, amount, testConfig.testId);

            _increasePricePerShare(testConfig.defaultAmount * 1_000);

            _mintAssetAndApproveForStrategy(amount, bob);
            prop_deposit(bob, alice, amount, testConfig.testId);
        }
    }

    function test__withdraw(uint8 fuzzAmount) public override {
        uint256 len = json.readUint(".length");
        for (uint256 i; i < len; i++) {
            if (i > 0) _setUpBaseTest(i, path);

            uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

            uint256 reqAssets = strategy.previewMint(strategy.previewWithdraw(amount));
            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            prop_withdraw(bob, bob, strategy.maxWithdraw(bob), testConfig.testId);

            _mintAssetAndApproveForStrategy(reqAssets, bob);
            vm.prank(bob);
            strategy.deposit(reqAssets, bob);

            _increasePricePerShare(testConfig.defaultAmount * 1_000);

            vm.prank(bob);
            strategy.approve(alice, type(uint256).max);

            prop_withdraw(alice, bob, strategy.maxWithdraw(bob), testConfig.testId);
        }
    }

    function test__setHarvestValues() public {
        address oldPool = address(strategyContract.stableSwapStETH());
        address newPool = address(0x85dE3ADd465a219EE25E04d22c39aB027cF5C12E);
        address stETH = strategyContract.stETH();

        strategyContract.setHarvestValues(newPool);
        uint256 oldAllowance = IERC20(stETH).allowance(address(strategy), oldPool);
        uint256 newAllowance = IERC20(stETH).allowance(address(strategy), newPool);

        assertEq(address(strategyContract.stableSwapStETH()), newPool);
        assertEq(oldAllowance, 0);
        assertEq(newAllowance, type(uint256).max);
    }

    function test__deposit_manual() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // check total assets
        assertEq(strategy.totalAssets(), amountDeposit);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // adapter should hold wstETH aToken in equal amount
        assertEq(awstETH.balanceOf(address(strategy)), amountDeposit + 1);

        // adapter should not hold debt at this poin
        assertEq(vdWETH.balanceOf(address(strategy)), 0);

        // LTV should still be 0
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__adjustLeverage_only_flashLoan_wstETH_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        // send the adapter some wstETH dust
        deal(address(strategy), 0.01e18);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit * 2);

        // all wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly lower target, since some wstETH means extra collateral
        assertGt(strategyContract.targetLTV(), strategyContract.getLTV());
    }

    function test__adjustLeverage_only_flashLoan() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit);

        uint256 slippageDebt = IwstETH(address(wstETH)).getWstETHByStETH(vdWETH.balanceOf(address(strategy)));
        slippageDebt = slippageDebt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

        assertApproxEqAbs(
            strategy.totalAssets(), amountDeposit - slippageDebt, _delta_, string.concat("totalAssets != expected")
        );

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is at target - or 1 wei delta for approximation up of ltv
        assertApproxEqAbs(strategyContract.targetLTV(), strategyContract.getLTV(), 1, string.concat("ltv != expected"));
    }

    function test__adjustLeverage_flashLoan_and_eth_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        uint256 totAssetsBefore = strategy.totalAssets();

        vm.deal(address(strategy), 1e18);

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // tot assets increased in this case
        // but if the amount of dust is lower than the slippage % of debt
        // totalAssets would be lower, as leverage incurred in debt
        assertGt(strategy.totalAssets(), totAssetsBefore);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly below target, since some eth dust has been deposited as collateral
        assertGt(strategyContract.targetLTV(), strategyContract.getLTV());
    }

    function test__adjustLeverage_only_eth_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountDust = 10e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // SEND ETH TO CONTRACT
        vm.deal(address(strategy), amountDust);

        // adjust leverage - should only trigger a dust amount deposit - no flashloans
        strategyContract.adjustLeverage();

        // check total assets - should be gt than totalDeposits
        assertGt(strategy.totalAssets(), amountDeposit);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(strategy)), amountDeposit);

        // adapter should not hold debt tokens
        assertEq(vdWETH.balanceOf(address(strategy)), 0);

        // adapter should now have 0 eth dust
        assertEq(address(strategy).balance, 0);

        // LTV is still zero
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__leverageDown() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        vm.prank(bob);
        strategy.withdraw(amountWithdraw, bob, bob);

        // after withdraw, vault ltv is a bit higher than target, considering the anti slipage amount witdrawn
        uint256 currentLTV = strategyContract.getLTV();
        assertGt(currentLTV, strategyContract.targetLTV());

        // HARVEST - should reduce leverage closer to target since we are above target LTV
        strategyContract.adjustLeverage();

        // ltv before should be higher than now
        assertGt(currentLTV, strategyContract.getLTV());
    }

    function test__withdraw_manual() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop - get debt
        strategyContract.adjustLeverage();

        // withdraw full amount - repay full debt
        uint256 amountWithd = strategy.totalAssets();

        vm.prank(bob);
        strategy.withdraw(amountWithd, bob, bob);

        // check total assets
        assertEq(strategy.totalAssets(), 0);

        // should not hold any wstETH
        assertApproxEqAbs(
            wstETH.balanceOf(address(strategy)), 0, _delta_, string.concat("more wstETH dust than expected")
        );

        // should not hold any wstETH aToken
        assertEq(awstETH.balanceOf(address(strategy)), 0);

        // adapter should not hold debt any debt
        assertEq(vdWETH.balanceOf(address(strategy)), 0);

        // adapter might have some dust ETH
        uint256 dust = address(strategy).balance;
        assertGt(dust, 0);

        // withdraw dust from owner
        uint256 aliceBalBefore = alice.balance;

        strategyContract.withdrawDust(alice);

        assertEq(alice.balance, aliceBalBefore + dust);
    }

    function test__setLeverageValues_lever_up() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = awstETH.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(8.5e17, 8.8e17);

        assertGt(awstETH.balanceOf(address(strategy)), oldABalance);
        assertGt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_lever_down() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(wstETH), bob, amountMint);

        vm.startPrank(bob);
        wstETH.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = awstETH.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(3e17, 4e17);

        assertLt(awstETH.balanceOf(address(strategy)), oldABalance);
        assertLt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_invalidInputs() public {
        // protocolLTV < targetLTV < maxLTV
        vm.expectRevert(
            abi.encodeWithSelector(WstETHLooper.InvalidLTV.selector, 3e18, 4e18, strategyContract.protocolMaxLTV())
        );
        strategyContract.setLeverageValues(3e18, 4e18);

        // maxLTV < targetLTV < protocolLTV
        vm.expectRevert(
            abi.encodeWithSelector(WstETHLooper.InvalidLTV.selector, 4e17, 3e17, strategyContract.protocolMaxLTV())
        );
        strategyContract.setLeverageValues(4e17, 3e17);
    }

    function test__setSlippage() public {
        uint256 oldSlippage = strategyContract.slippage();
        uint256 newSlippage = oldSlippage + 1;
        strategyContract.setSlippage(newSlippage);

        assertNotEq(oldSlippage, strategyContract.slippage());
        assertEq(strategyContract.slippage(), newSlippage);
    }

    function test__setSlippage_invalidValue() public {
        uint256 newSlippage = 1e18; // 100%

        vm.expectRevert(abi.encodeWithSelector(WstETHLooper.InvalidSlippage.selector, newSlippage, 2e17));
        strategyContract.setSlippage(newSlippage);
    }

    function test__invalid_flashLoan() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory premiums = new uint256[](1);

        // reverts with invalid msg.sender and valid initiator
        vm.expectRevert(WstETHLooper.NotFlashLoan.selector);
        vm.prank(bob);
        strategyContract.executeOperation(assets, amounts, premiums, address(strategy), "");

        // reverts with invalid initiator and valid msg.sender
        vm.expectRevert(WstETHLooper.NotFlashLoan.selector);
        vm.prank(address(lendingPool));
        strategyContract.executeOperation(assets, amounts, premiums, address(bob), "");
    }

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        // LTV should be 0
        assertEq(strategyContract.getLTV(), 0);

        strategy.harvest(hex"");

        // LTV should be at target now
        assertApproxEqAbs(strategyContract.targetLTV(), strategyContract.getLTV(), 1, string.concat("ltv != expected"));
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public {
        assertEq(strategy.asset(), address(wstETH), "asset");
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat("VaultCraft Leveraged ", IERC20Metadata(address(wstETH)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vc-", IERC20Metadata(address(wstETH)).symbol()),
            "symbol"
        );

        assertApproxEqAbs(wstETH.allowance(address(strategy), address(lendingPool)), type(uint256).max, 1, "allowance");
    }
}
