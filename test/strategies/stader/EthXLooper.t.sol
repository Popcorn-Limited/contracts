// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {
    ETHXLooper,
    LooperInitValues,
    IERC20,
    IERC20Metadata,
    IETHxStaking,
    ILendingPool,
    IProtocolDataProvider,
    Math
} from "src/strategies/stader/ETHxLooper.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";

contract ETHXLooperTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IERC20 ethX;
    IERC20 aEthX;
    IERC20 vdWETH;
    ILendingPool lendingPool;
    ETHXLooper strategyContract;
    IETHxStaking stakingPool = IETHxStaking(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
    IProtocolDataProvider public protocolDataProvider;

    uint256 defaultAmount;
    uint256 slippage;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/stader/ETHXLooperTestConfig.json");
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
        ETHXLooper strategy = new ETHXLooper();

        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(looperInitValues));

        strategyContract = ETHXLooper(payable(strategy));

        ethX = IERC20(testConfig_.asset);
        aEthX = strategyContract.interestToken();
        vdWETH = strategyContract.debtToken();
        lendingPool = strategyContract.lendingPool();
        defaultAmount = testConfig_.defaultAmount;
        slippage = strategyContract.slippage();
        protocolDataProvider = IProtocolDataProvider(strategyContract.protocolDataProvider());

        deal(testConfig_.asset, address(this), 1);
        IERC20(testConfig_.asset).approve(address(strategy), 1);
        strategyContract.setUserUseReserveAsCollateral(1);

        return IBaseStrategy(address(strategy));
    }

    // Verify that totalAssets returns the expected amount
    function test__verify_totalAssets() public {
        // Make sure totalAssets isnt 0
        deal(address(ethX), bob, defaultAmount);
        vm.startPrank(bob);
        ethX.approve(address(strategy), defaultAmount);
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
        deal(address(ethX), address(strategy), amount);
        vm.startPrank(address(strategy));
        lendingPool.supply(address(ethX), amount, address(strategy), 0);
        vm.stopPrank();
    }

    function test__initialization() public override {
        LooperInitValues memory looperInitValues = abi.decode(json.parseRaw(string.concat(".configs[0].specific.init")), (LooperInitValues));

        // Deploy Strategy
        ETHXLooper strategy = new ETHXLooper();

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

    function test__maxDeposit() public override {
        (uint256 borrowCap, uint256 supplyCap) = protocolDataProvider.getReserveCaps(strategy.asset());

        uint256 expectedCap = supplyCap * 1e18 - aEthX.totalSupply();
        
        assertEq(strategy.maxDeposit(bob), expectedCap);

        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);
        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        vm.prank(address(this));
        strategy.pause();

        assertEq(strategy.maxDeposit(bob), 0);
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
        address oldPool = address(strategyContract.stableSwapPool());
        address newPool = address(0x85dE3ADd465a219EE25E04d22c39aB027cF5C12E);
        address asset = strategy.asset();

        strategyContract.setHarvestValues(newPool);
        uint256 oldAllowance = IERC20(asset).allowance(address(strategy), oldPool);
        uint256 newAllowance = IERC20(asset).allowance(address(strategy), newPool);

        assertEq(address(strategyContract.stableSwapPool()), newPool);
        assertEq(oldAllowance, 0);
        assertEq(newAllowance, type(uint256).max);
    }

    function test__deposit_manual() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // check total assets
        assertEq(strategy.totalAssets(), amountDeposit);

        // ethX should be in lending market
        assertEq(ethX.balanceOf(address(strategy)), 0);

        // adapter should hold ethX aToken in equal amount
        assertEq(aEthX.balanceOf(address(strategy)), amountDeposit + 1);

        // adapter should not hold debt at this poin
        assertEq(vdWETH.balanceOf(address(strategy)), 0);

        // LTV should still be 0
        assertEq(strategyContract.getLTV(), 0);
    }

    function test__adjustLeverage_only_flashLoan_ethX_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(ethX), bob, amountMint);

        // send the adapter some ethX dust
        deal(address(strategy), 0.01e18);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit * 2);

        // all ethX should be in lending market
        assertEq(ethX.balanceOf(address(strategy)), 0);

        // adapter should now have more ethX aToken than before
        assertGt(aEthX.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is slightly lower target, since some ethX means extra collateral
        assertGt(strategyContract.targetLTV(), strategyContract.getLTV());
    }

    function test__adjustLeverage_only_flashLoan() public {
        uint256 amountMint = 1e18;
        uint256 amountDeposit = 1e18;
        uint256 ethToEthXRate = stakingPool.getExchangeRate();

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit);

        uint256 slippageDebt = vdWETH.balanceOf(address(strategy)).mulDiv(1e18, ethToEthXRate, Math.Rounding.Ceil);

        slippageDebt = slippageDebt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);
        
        assertApproxEqAbs(
            strategy.totalAssets(), amountDeposit - slippageDebt, _delta_, string.concat("totalAssets != expected")
        );

        // ethX should be in lending market
        assertEq(ethX.balanceOf(address(strategy)), 0);

        // adapter should now have more ethX aToken than before
        assertGt(aEthX.balanceOf(address(strategy)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(strategyContract.getLTV(), 0);

        // LTV is at target - or 1 wei delta for approximation up of ltv
        assertApproxEqAbs(strategyContract.targetLTV(), strategyContract.getLTV(), _delta_, string.concat("ltv != expected"));
    }

    function test__adjustLeverage_flashLoan_and_eth_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
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

        // ethX should be in lending market
        assertEq(ethX.balanceOf(address(strategy)), 0);

        // adapter should now have more ethX aToken than before
        assertGt(aEthX.balanceOf(address(strategy)), amountDeposit);

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

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // SEND eth TO CONTRACT
        vm.deal(address(strategy), amountDust);

        // adjust leverage - should only trigger a dust amount deposit - no flashloans
        strategyContract.adjustLeverage();

        // check total assets - should be gt than totalDeposits
        assertGt(strategy.totalAssets(), amountDeposit);

        // ethX should be in lending market
        assertEq(ethX.balanceOf(address(strategy)), 0);

        // adapter should now have more ethX aToken than before
        assertGt(aEthX.balanceOf(address(strategy)), amountDeposit);

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

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
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
        uint256 amountMint = 1e18;
        uint256 amountDeposit = 1e18;

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();
        

        // HARVEST - trigger leverage loop - get debt
        strategyContract.adjustLeverage();

        // withdraw full amount - repay full debt
        uint256 amountWithd = strategy.totalAssets() - 1;
        vm.prank(bob);
        strategy.withdraw(amountWithd, bob, bob);

        // check total assets
        assertEq(strategy.totalAssets(), 0);

        // should not hold any ethX
        assertApproxEqAbs(
            ethX.balanceOf(address(strategy)), 0, _delta_, string.concat("more ethX dust than expected")
        );

        // should not hold any ethX aToken
        assertEq(aEthX.balanceOf(address(strategy)), 0);

        // adapter should not hold debt any debt
        assertEq(vdWETH.balanceOf(address(strategy)), 0);
    }

    function test__setLeverageValues_lever_up() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = aEthX.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(8.5e17, 8.8e17);

        assertGt(aEthX.balanceOf(address(strategy)), oldABalance);
        assertGt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_lever_down() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(address(ethX), bob, amountMint);

        vm.startPrank(bob);
        ethX.approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        strategyContract.adjustLeverage();

        uint256 oldABalance = aEthX.balanceOf(address(strategy));
        uint256 oldLTV = strategyContract.getLTV();

        strategyContract.setLeverageValues(3e17, 4e17);

        assertLt(aEthX.balanceOf(address(strategy)), oldABalance);
        assertLt(strategyContract.getLTV(), oldLTV);
    }

    function test__setLeverageValues_invalidInputs() public {
        // protocolLTV < targetLTV < maxLTV
        vm.expectRevert(
            abi.encodeWithSelector(ETHXLooper.InvalidLTV.selector, 3e18, 4e18, strategyContract.protocolMaxLTV())
        );
        strategyContract.setLeverageValues(3e18, 4e18);

        // maxLTV < targetLTV < protocolLTV
        vm.expectRevert(
            abi.encodeWithSelector(ETHXLooper.InvalidLTV.selector, 4e17, 3e17, strategyContract.protocolMaxLTV())
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

        vm.expectRevert(abi.encodeWithSelector(ETHXLooper.InvalidSlippage.selector, newSlippage, 2e17));
        strategyContract.setSlippage(newSlippage);
    }

    function test__invalid_flashLoan() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory premiums = new uint256[](1);

        // reverts with invalid msg.sender and valid initiator
        vm.expectRevert(ETHXLooper.NotFlashLoan.selector);
        vm.prank(bob);
        strategyContract.executeOperation(assets, amounts, premiums, address(strategy), "");

        // reverts with invalid initiator and valid msg.sender
        vm.expectRevert(ETHXLooper.NotFlashLoan.selector);
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
        assertApproxEqAbs(strategyContract.targetLTV(), strategyContract.getLTV(), _delta_, string.concat("ltv != expected"));
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public {
        assertEq(strategy.asset(), address(ethX), "asset");
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat("VaultCraft Leveraged ", IERC20Metadata(address(ethX)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vc-", IERC20Metadata(address(ethX)).symbol()),
            "symbol"
        );

        assertApproxEqAbs(ethX.allowance(address(strategy), address(lendingPool)), type(uint256).max, 1, "allowance");
    }
}
