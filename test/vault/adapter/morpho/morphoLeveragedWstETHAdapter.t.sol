// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {MorphoLeveragedWstETHAdapter, IMorpho, SafeERC20, IERC20, IERC20Metadata, Math, IwstETH} from "../../../../src/vault/adapter/morpho/LeveragedWstETHAdapter.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {MorphoLevWstETHTestConfigStorage} from "./morphoConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {ICurveMetapool} from "../../../../src/interfaces/external/curve/ICurveMetapool.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract LeveragedWstETHAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 awstETH = IERC20(0x0B925eD163218f6662a35e0f0371Ac234f9E9371); // interest token aave    
    IERC20 vdWETH = IERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE); // variable debt token aave         
    IMorpho morpho =
        IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // morpho

    uint256 slippage = 1e15;

    MorphoLeveragedWstETHAdapter adapterContract;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 19333530);
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new MorphoLevWstETHTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));

        defaultAmount = 1e18;

        minFuzz = 1e18;
        minShares = 1e27;

        raise = defaultAmount * 1_000;

        maxAssets = minFuzz * 10;
        maxShares = minShares * 10;
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        setUpBaseTest(
            wstETH,
            address(new MorphoLeveragedWstETHAdapter()),
            address(morpho),
            10,
            "Leveraged wstETH  ",
            false
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            address(morpho),
            testConfig
        );

        adapterContract = MorphoLeveragedWstETHAdapter(payable(address(adapter)));
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

    function test_deposit1() public {
        uint256 amountMint = 10e18;
        uint256 amountDeposit = 1e18;
        uint256 amountWithdraw = 5e17;

        deal(address(asset), bob, amountMint);

        vm.startPrank(bob);
        asset.approve(address(adapter), amountMint);
        adapter.deposit(amountDeposit, bob);
        vm.stopPrank();

        // check total assets
        assertEq(adapter.totalAssets(), amountDeposit + 1);

        // wstETH should be in lending market
        assertEq(wstETH.balanceOf(address(adapter)), 0);

        // adapter should hold wstETH aToken in equal amount
        assertEq(awstETH.balanceOf(address(adapter)), amountDeposit + 1);

        // adapter should not hold debt at this poin
        assertEq(vdWETH.balanceOf(address(adapter)), 0);

        // LTV should still be 0
        assertEq(adapterContract.getLTV(), 0);
    }

    function test_leverageUp() public {
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

        // LTV is at target
        assertEq(adapterContract.targetLTV(), adapterContract.getLTV());
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
        vm.prank(bob);
        adapter.withdraw(amountWithd, bob, bob);

        // check total assets
        assertEq(adapter.totalAssets(), 0);

        // should not hold any wstETH
        assertApproxEqAbs(
            wstETH.balanceOf(address(adapter)),
            0,
            _delta_,
            string.concat("more wstETH dust than expected", baseTestId)
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

        adapterContract.setLeverageValues(6.5e17, 7e17, 1e15);

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

        adapterContract.setLeverageValues(3e17, 4e17, 1e15);

        assertLt(awstETH.balanceOf(address(adapter)), oldABalance);
        assertLt(adapterContract.getLTV(), oldLTV);
    }

    function testFail_invalid_flashLoan() public {
        vm.prank(bob);
        adapterContract.onMorphoFlashLoan(100, hex"");

        vm.prank(address(adapter));
        adapterContract.onMorphoFlashLoan(100, hex"");
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
            asset.allowance(address(adapter), address(morpho)),
            type(uint256).max,
            "allowance"
        );
    }
}
