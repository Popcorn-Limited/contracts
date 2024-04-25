// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {WstETHLooper, IERC20, IwstETH, ILendingPool} from "../../../src/strategies/lido/WstETHLooper.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";

struct LooperValues {
    address aaveDataProvider;
    uint256 maxLTV;
    address poolAddressProvider;
    uint256 slippage;
    uint256 targetLTV;
}

contract WstETHLooperTest is BaseStrategyTest {
    using stdJson for string;

    IERC20 wstETH;
    IERC20 awstETH;
    IERC20 vdWETH;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/lido/WstETHLooperTestConfig.json");
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        // Read strategy init values
        LooperValues memory looperValues = abi.decode(
            json_.parseRaw(
                string.concat(".configs[", index_, "].specific.init")
            ),
            (LooperValues)
        );

        // Deploy Strategy
        WstETHLooper strategy = new WstETHLooper();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            false,
            abi.encode(
                looperValues.poolAddressProvider,
                looperValues.aaveDataProvider,
                looperValues.slippage,
                looperValues.targetLTV,
                looperValues.maxLTV
            )
        );

        wstETH = IERC20(testConfig_.asset);
        awstETH = strategy.interestToken();
        vdWETH = strategy.debtToken();

        deal(testConfig_.asset, address(this), 1);
        IERC20(testConfig_.asset).approve(address(strategy), 1);
        strategy.setUserUseReserveAsCollateral(1);

        return IBaseStrategy(address(strategy));
    }

    function _increasePricePerShare(uint256) internal override {
        deal(testConfig.asset, address(strategy), 10 ether);

        ILendingPool lendingPool_ = WstETHLooper(payable(address(strategy)))
            .lendingPool();

        vm.startPrank(address(strategy));
        lendingPool_.supply(
            address(testConfig.asset),
            10 ether,
            address(strategy),
            0
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    function test_deposit() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(testConfig.asset, bob, amountMint);

        vm.startPrank(bob);
        IERC20(testConfig.asset).approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // check total assets
        assertEq(strategy.totalAssets(), amountDeposit + 1);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // strategy should hold wstETH aToken in equal amount
        assertEq(awstETH.balanceOf(address(strategy)), amountDeposit + 1);

        // strategy should not hold debt at this poin
        assertEq(vdWETH.balanceOf(address(strategy)), 0);

        // LTV should still be 0
        assertEq(WstETHLooper(payable(address(strategy))).getLTV(), 0);
    }

    function test_leverageUp() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(testConfig.asset, bob, amountMint);

        vm.startPrank(bob);
        IERC20(testConfig.asset).approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        WstETHLooper(payable(address(strategy))).adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(strategy.totalAssets(), amountDeposit);

        uint256 slippageDebt = IwstETH(address(wstETH)).getWstETHByStETH(
            vdWETH.balanceOf(address(strategy))
        );
        slippageDebt = Math.mulDiv(
            slippageDebt,
            json.readUint(".configs[0].specific.init.slippage"),
            1e18,
            Math.Rounding.Ceil
        );

        assertApproxEqAbs(
            strategy.totalAssets(),
            amountDeposit - slippageDebt,
            _delta_,
            "totalAssets != expected"
        );

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(strategy)), 0);

        // strategy should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(strategy)), amountDeposit);

        // strategy should hold debt tokens
        assertGt(vdWETH.balanceOf(address(strategy)), 0);

        // LTV is non zero now
        assertGt(WstETHLooper(payable(address(strategy))).getLTV(), 0);

        // LTV is at target
        assertEq(
            WstETHLooper(payable(address(strategy))).targetLTV(),
            WstETHLooper(payable(address(strategy))).getLTV()
        );
    }

    function test_leverageDown() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(testConfig.asset, bob, amountMint);

        vm.startPrank(bob);
        IERC20(testConfig.asset).approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        WstETHLooper(payable(address(strategy))).adjustLeverage();

        vm.prank(bob);
        strategy.withdraw(amountWithdraw, bob, bob);

        // after withdraw, vault ltv is a bit higher than target, considering the anti slipage amount witdrawn
        uint256 currentLTV = WstETHLooper(payable(address(strategy))).getLTV();
        assertGt(
            currentLTV,
            WstETHLooper(payable(address(strategy))).targetLTV()
        );

        // HARVEST - should reduce leverage closer to target since we are above target LTV
        WstETHLooper(payable(address(strategy))).adjustLeverage();

        // ltv before should be higher than now
        assertGt(currentLTV, WstETHLooper(payable(address(strategy))).getLTV());
    }

    function test_withdraw() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(testConfig.asset, bob, amountMint);

        vm.startPrank(bob);
        IERC20(testConfig.asset).approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop - get debt
        WstETHLooper(payable(address(strategy))).adjustLeverage();

        // withdraw full amount - repay full debt
        uint256 amountWithd = strategy.totalAssets();
        vm.prank(bob);
        strategy.withdraw(amountWithd, bob, bob);

        // check total assets
        assertEq(strategy.totalAssets(), 0);

        // should not hold any wstETH
        assertApproxEqAbs(
            wstETH.balanceOf(address(strategy)),
            0,
            _delta_,
            "more wstETH dust than expected"
        );

        // should not hold any wstETH aToken
        assertEq(awstETH.balanceOf(address(strategy)), 0);

        // strategy should not hold debt any debt
        assertEq(vdWETH.balanceOf(address(strategy)), 0);

        // strategy might have some dust ETH
        uint256 dust = address(strategy).balance;
        assertGt(dust, 0);

        // withdraw dust from owner
        uint256 aliceBalBefore = alice.balance;

        WstETHLooper(payable(address(strategy))).withdrawDust(alice);

        assertEq(alice.balance, aliceBalBefore + dust);
    }

    function test_setLeverageValues_lever_up() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(testConfig.asset, bob, amountMint);

        vm.startPrank(bob);
        IERC20(testConfig.asset).approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        WstETHLooper(payable(address(strategy))).adjustLeverage();

        uint256 oldABalance = awstETH.balanceOf(address(strategy));
        uint256 oldLTV = WstETHLooper(payable(address(strategy))).getLTV();

        WstETHLooper(payable(address(strategy))).setLeverageValues(
            8.5e17,
            8.8e17
        );

        assertGt(awstETH.balanceOf(address(strategy)), oldABalance);
        assertGt(WstETHLooper(payable(address(strategy))).getLTV(), oldLTV);
    }

    function test_setLeverageValues_lever_down() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;

        deal(testConfig.asset, bob, amountMint);

        vm.startPrank(bob);
        IERC20(testConfig.asset).approve(address(strategy), amountMint);
        strategy.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        WstETHLooper(payable(address(strategy))).adjustLeverage();

        uint256 oldABalance = awstETH.balanceOf(address(strategy));
        uint256 oldLTV = WstETHLooper(payable(address(strategy))).getLTV();

        WstETHLooper(payable(address(strategy))).setLeverageValues(3e17, 4e17);

        assertLt(awstETH.balanceOf(address(strategy)), oldABalance);
        assertLt(WstETHLooper(payable(address(strategy))).getLTV(), oldLTV);
    }

    function test_setSlippage() public {
        uint256 oldSlippage = WstETHLooper(payable(address(strategy)))
            .slippage();
        uint256 newSlippage = oldSlippage + 1;
        WstETHLooper(payable(address(strategy))).setSlippage(newSlippage);

        assertNotEq(
            oldSlippage,
            WstETHLooper(payable(address(strategy))).slippage()
        );
        assertEq(
            WstETHLooper(payable(address(strategy))).slippage(),
            newSlippage
        );
    }

    function testFail_invalid_flashLoan() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory premiums = new uint256[](1);

        vm.prank(bob);
        WstETHLooper(payable(address(strategy))).executeOperation(
            assets,
            amounts,
            premiums,
            bob,
            ""
        );

        vm.prank(address(strategy));
        WstETHLooper(payable(address(strategy))).executeOperation(
            assets,
            amounts,
            premiums,
            bob,
            ""
        );
    }

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        vm.warp(block.timestamp + 12);

        // LTV should be 0
        assertEq(WstETHLooper(payable(address(strategy))).getLTV(), 0);

        strategy.harvest();

        // LTV should be at target now
        assertEq(
            WstETHLooper(payable(address(strategy))).targetLTV(),
            WstETHLooper(payable(address(strategy))).getLTV()
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}
