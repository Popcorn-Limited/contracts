// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {LeveragedWstETHAdapter, SafeERC20, IERC20, IERC20Metadata, Math, ILendingPool, IwstETH} from "../../../../src/vault/adapter/lido/LeveragedWstETHAdapter.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {LevWstETHTestConfigStorage, LevWstETHTestConfig} from "./wstETHTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {ICurveMetapool} from "../../../../src/interfaces/external/curve/ICurveMetapool.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import "forge-std/console.sol";

contract LeveragedWstETHAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 awstETH; // interest token
    IERC20 vdWETH; // variable debt token
    ILendingPool lendingPool;
    address aaveDataProvider;
    address poolAddressesProvider;
    uint256 slippage;
    uint256 slippageCap;
    uint256 targetLTV;
    uint256 maxLTV;

    LeveragedWstETHAdapter adapterContract;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 19333530);
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new LevWstETHTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(1));

        defaultAmount = 1e18;

        minFuzz = 1e18;
        minShares = 1e27;

        raise = defaultAmount * 1_000;

        maxAssets = minFuzz * 1_000;
        maxShares = minShares * 10;
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        setUpBaseTest(
            wstETH,
            address(new LeveragedWstETHAdapter()),
            aaveDataProvider,
            10,
            "Leveraged wstETH  ",
            false
        );

        (    
            address awstETH_,
            address vdWETH_,
            address lendingPool_,
            address dataProvider_,
            address poolAddressesProvider_,
            uint256 slippage_,
            uint256 slippageCap_,
            uint256 targetLTV_,
            uint256 maxLTV_
        ) = abi.decode(testConfig, (
            address,address,address,address,address,uint256,uint256,uint256,uint256
        ));

        awstETH = IERC20(awstETH_);
        vdWETH = IERC20(vdWETH_);
        lendingPool = ILendingPool(lendingPool_);
        aaveDataProvider = dataProvider_;
        poolAddressesProvider = poolAddressesProvider_;
        slippage = slippage_;
        slippageCap = slippageCap_;
        targetLTV = targetLTV_;
        maxLTV = maxLTV_;

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            aaveDataProvider,
            abi.encode(poolAddressesProvider,slippage,slippageCap,targetLTV,maxLTV)
        );

        adapterContract = LeveragedWstETHAdapter(payable(address(adapter)));

        uint256 actualVaultMode = lendingPool.getUserEMode(address(adapter));
        assertEq(actualVaultMode, 1);

        deal(address(asset), address(this), 1);
        IERC20(asset).approve(address(adapter), 1);
        adapterContract.setUserUseReserveAsCollateral(1);
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function test_verify_totalAssets() public {
        // Make sure totalAssets isnt 0
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            _delta_,
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    function increasePricePerShare(uint256 amount) public override {
        deal(address(wstETH), address(adapter), 10 ether);
        vm.startPrank(address(adapter));
        lendingPool.supply(address(wstETH), 10 ether, address(adapter), 0);
        vm.stopPrank();
    }

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            aaveDataProvider,
            abi.encode(poolAddressesProvider,slippage,slippageCap,targetLTV,maxLTV)
        );

        assertEq(adapter.owner(), address(this), "owner");
        assertEq(adapter.strategy(), address(strategy), "strategy");
        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
        assertEq(adapter.strategyConfig(), "", "strategyConfig");
        assertEq(
            IERC20Metadata(address(adapter)).decimals(),
            IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
            "decimals"
        );

        verify_adapterInit();
    }

    function test__deposit(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

            _mintAssetAndApproveForAdapter(amount, bob);

            prop_deposit(bob, bob, amount, testId);

            increasePricePerShare(raise);

            _mintAssetAndApproveForAdapter(amount, bob);
            prop_deposit(bob, alice, amount, testId);
        }
    }

    function test__withdraw(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

            uint256 reqAssets = adapter.previewMint(
                adapter.previewWithdraw(amount)
            );
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            prop_withdraw(bob, bob, adapter.maxWithdraw(bob), testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);

            prop_withdraw(alice, bob, adapter.maxWithdraw(bob), testId);
        }
    }

    function test_deposit() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // check total assets
        assertEq(adapter.totalAssets(), amountDeposit);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(adapter)), 0);

        // adapter should hold wstETH aToken in equal amount
        assertEq(awstETH.balanceOf(address(adapter)), amountDeposit + 1);

        // adapter should not hold debt at this poin
        assertEq(vdWETH.balanceOf(address(adapter)), 0);

        // LTV should still be 0
        assertEq(adapterContract.getLTV(), 0);
    }

    function test_adjustLeverage_only_flahsLoan_wstETH_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        // send the adapter some wstETH dust
        deal(address(asset), address(adapter), amountDeposit);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(adapter.totalAssets(), amountDeposit * 2);

        // all wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(adapter)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(adapter)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(adapter)), 0);

        // LTV is non zero now
        assertGt(adapterContract.getLTV(), 0);

        // LTV is slightly lower target, since some wstETH means extra collateral
        assertGt(
            adapterContract.targetLTV(), 
            adapterContract.getLTV()
        );
    }

    function test_adjustLeverage_only_flahsLoan() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        // check total assets - should be lt than totalDeposits
        assertLt(adapter.totalAssets(), amountDeposit);

        uint256 slippageDebt = IwstETH(address(wstETH)).getWstETHByStETH(
            vdWETH.balanceOf(address(adapter))
        );
        slippageDebt = slippageDebt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

        assertApproxEqAbs(
            adapter.totalAssets(),
            amountDeposit - slippageDebt,
            _delta_,
            string.concat("totalAssets != expected", baseTestId)
        );

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(adapter)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(adapter)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(adapter)), 0);

        // LTV is non zero now
        assertGt(adapterContract.getLTV(), 0);

        // LTV is at target - or 1 wei delta for approximation up of ltv
        assertApproxEqAbs(
            adapterContract.targetLTV(), 
            adapterContract.getLTV(),
            1,
            string.concat("ltv != expected", baseTestId)
        );
    }

    function test_adjustLeverage_flashLoan_and_eth_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        uint256 totAssetsBefore = adapter.totalAssets();

        vm.deal(address(adapter), 1e18);

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        // tot assets increased in this case
        // but if the amount of dust is lower than the slippage % of debt 
        // totalAssets would be lower, as leverage incurred in debt
        assertGt(
            adapter.totalAssets(),
            totAssetsBefore
        );

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(adapter)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(adapter)), amountDeposit);

        // adapter should hold debt tokens
        assertGt(vdWETH.balanceOf(address(adapter)), 0);

        // LTV is non zero now
        assertGt(adapterContract.getLTV(), 0);

        // LTV is slightly below target, since some eth dust has been deposited as collateral
        assertGt(
            adapterContract.targetLTV(), 
            adapterContract.getLTV()
        );
    }

    function test_adjustLeverage_only_eth_dust() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;
        uint256 amountDust = 10e18;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // SEND ETH TO CONTRACT 
        vm.deal(address(adapter), amountDust);

        // adjust leverage - should only trigger a dust amount deposit - no flashloans
        adapterContract.adjustLeverage();
        
        // check total assets - should be gt than totalDeposits
        assertGt(adapter.totalAssets(), amountDeposit);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(adapter)), 0);

        // adapter should now have more wstETH aToken than before
        assertGt(awstETH.balanceOf(address(adapter)), amountDeposit);

        // adapter should not hold debt tokens
        assertEq(vdWETH.balanceOf(address(adapter)), 0);

        // adapter should now have 0 eth dust
        assertEq(address(adapter).balance, 0);

        // LTV is still zero
        assertEq(adapterContract.getLTV(), 0);
    }

    function test_leverageDown() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        vm.prank(bob);
        adapter.withdraw(amountWithdraw, bob, bob);

        // after withdraw, vault ltv is a bit higher than target, considering the anti slipage amount witdrawn
        uint256 currentLTV = adapterContract.getLTV();
        assertGt(currentLTV, adapterContract.targetLTV());

        // HARVEST - should reduce leverage closer to target since we are above target LTV
        adapterContract.adjustLeverage();

        // ltv before should be higher than now
        assertGt(currentLTV, adapterContract.getLTV());
    }

    function test_withdraw() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop - get debt
        adapterContract.adjustLeverage();

        // withdraw full amount - repay full debt
        uint256 amountWithd = adapter.totalAssets();
        console.log(amountWithd);

        vm.prank(bob);
        adapter.withdraw(amountWithd, bob, bob);

        // check total assets
        assertEq(adapter.totalAssets(), 0);

        // should not hold any wstETH
        assertApproxEqAbs(
            wstETH.balanceOf(address(adapter)),
            0,
            _delta_,
            string.concat("more wstETH dust than expected")
        );

        // should not hold any wstETH aToken
        assertEq(awstETH.balanceOf(address(adapter)), 0);

        // adapter should not hold debt any debt
        assertEq(vdWETH.balanceOf(address(adapter)), 0);

        // adapter might have some dust ETH
        uint256 dust = address(adapter).balance;
        assertGt(dust, 0);

        // withdraw dust from owner
        uint256 aliceBalBefore = alice.balance;

        adapterContract.withdrawDust(alice);

        assertEq(alice.balance, aliceBalBefore + dust);
    }

    function test_setLeverageValues_lever_up() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        uint256 oldABalance = awstETH.balanceOf(address(adapter));
        uint256 oldLTV = adapterContract.getLTV();

        adapterContract.setLeverageValues(8.5e17, 8.8e17);

        assertGt(awstETH.balanceOf(address(adapter)), oldABalance);
        assertGt(adapterContract.getLTV(), oldLTV);
    }

    function test_setLeverageValues_lever_down() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        uint256 oldABalance = awstETH.balanceOf(address(adapter));
        uint256 oldLTV = adapterContract.getLTV();

        adapterContract.setLeverageValues(3e17, 4e17);

        assertLt(awstETH.balanceOf(address(adapter)), oldABalance);
        assertLt(adapterContract.getLTV(), oldLTV);
    }

    function test_setLeverageValues_invalidInputs() public {
        // protocolLTV < targetLTV < maxLTV
        vm.expectRevert(abi.encodeWithSelector(
            LeveragedWstETHAdapter.InvalidLTV.selector,
            3e18,
            4e18,
            adapterContract.protocolLMaxLTV()
        ));
        adapterContract.setLeverageValues(3e18, 4e18);

        // maxLTV < targetLTV < protocolLTV
        vm.expectRevert(abi.encodeWithSelector(
            LeveragedWstETHAdapter.InvalidLTV.selector,
            4e17,
            3e17,
            adapterContract.protocolLMaxLTV()
        ));
        adapterContract.setLeverageValues(4e17, 3e17);
    }

    function test_setSlippage() public {
        uint256 oldSlippage = adapterContract.slippage();
        uint256 newSlippage = oldSlippage + 1;
        adapterContract.setSlippage(newSlippage);

        assertNotEq(oldSlippage, adapterContract.slippage());
        assertEq(adapterContract.slippage(), newSlippage);
    }

    function test_setSlippage_invalidValue() public {
        uint256 newSlippage = 1e18; // 100%

        vm.expectRevert(
            abi.encodeWithSelector(
                LeveragedWstETHAdapter.InvalidSlippage.selector, newSlippage, 1e17
            )
        );
        adapterContract.setSlippage(newSlippage);
    }

    function test_invalid_flashLoan() public {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory premiums = new uint256[](1);

        // reverts with invalid msg.sender and valid initiator
        vm.expectRevert(LeveragedWstETHAdapter.NotFlashLoan.selector);
        vm.prank(bob);
        adapterContract.executeOperation(assets,amounts,premiums,address(adapter), "");

        // reverts with invalid initiator and valid msg.sender
        vm.expectRevert(LeveragedWstETHAdapter.NotFlashLoan.selector);
        vm.prank(address(lendingPool));
        adapterContract.executeOperation(assets,amounts,premiums,address(bob), "");
    }

    function test__harvest() public override {
        _mintAssetAndApproveForAdapter(100e18, bob);

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        // LTV should be 0
        assertEq(adapterContract.getLTV(), 0);

        adapter.harvest();

        // LTV should be at target now
        assertApproxEqAbs(
            adapterContract.targetLTV(), 
            adapterContract.getLTV(),
            1,
            string.concat("ltv != expected", baseTestId)    
        );
    }

    function test__disable_auto_harvest() public override {
        adapter.toggleAutoHarvest();
        assertTrue(adapter.autoHarvest());

        _mintAssetAndApproveForAdapter(defaultAmount, bob);
        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 lastHarvest = adapter.lastHarvest();

        assertEq(lastHarvest, block.timestamp, "should auto harvest");
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(wstETH), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Leveraged ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(lendingPool)),
            type(uint256).max,
            "allowance"
        );
    }
}
