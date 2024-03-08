// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {
    LeveragedWstETHAdapter,
    SafeERC20,
    IERC20,
    IERC20Metadata,
    Math,
    ILendingPool
} from "../../../../src/vault/adapter/lido/LeveragedWstETHAdapter.sol";
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
    ICurveMetapool public constant StableSwapSTETH = ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // IERC20 awstETH = IERC20(0x0B925eD163218f6662a35e0f0371Ac234f9E9371); // interest token aave
    IERC20 awstETH = IERC20(0x12B54025C112Aa61fAce2CDB7118740875A566E9); // interest token spark

    // IERC20 vdWETH = IERC20(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE); // variable debt token aave
    IERC20 vdWETH = IERC20(0x2e7576042566f8D6990e07A1B61Ad1efd86Ae70d); // variable debt token spark

    // ILendingPool lendingPool = ILendingPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); // aave
    ILendingPool lendingPool = ILendingPool(0xC13e21B648A5Ee794902342038FF3aDAB66BE987); // spark

    // address aaveDataProvider = address(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3); //aave
    address aaveDataProvider = address(0xFc21d6d146E6086B8359705C8b28512a983db0cb); //spark

    LeveragedWstETHAdapter adapterContract;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 19333530);
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(address(new LevWstETHTestConfigStorage()));

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
            address(new LeveragedWstETHAdapter()),
            0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2,
            10,
            "Leveraged wstETH  ",
            false
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(abi.encode(asset, address(this), address(0), 0, sigs, ""), aaveDataProvider, testConfig);

        adapterContract = LeveragedWstETHAdapter(payable(address(adapter)));
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
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

    function test_depositAndLeverage() public {
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
        assertEq(awstETH.balanceOf(address(adapter)), amountDeposit);

        // adapter should not hold debt at this poin
        assertEq(vdWETH.balanceOf(address(adapter)), 0);

        // LTV should still be 0
        assertEq(adapterContract.getLTV(), 0);

        // HARVEST - trigger leverage loop
        adapterContract.adjustLeverage();

        // check total assets
        // assertEq(adapter.totalAssets(), amountDeposit); // 1 wei error TODO

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

        // withdraw partial amount
        vm.prank(bob);
        adapter.withdraw(amountWithdraw, bob, bob);
        // console.log(adapter.totalAssets(), amountWithdraw);
        // console.log(wstETH.balanceOf(address(adapter)));
        // console.log(IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).balanceOf(address(adapter)));
        // console.log(address(adapter).balance);

        // after withdraw, vault ltv is a bit higher than target, considering the anti slipage amount witdrawn
        uint256 currentLTV = adapterContract.getLTV();
        assertGt(currentLTV, adapterContract.targetLTV());

        // HARVEST - should reduce leverage closer to target since we are above target LTV
        adapterContract.adjustLeverage();

        // ltv before should be higher than now
        assertGt(currentLTV, adapterContract.getLTV());

        // withdraw full amount - repay full debt
        uint256 amountWithd = adapter.totalAssets();
        vm.prank(bob);
        adapter.withdraw(amountWithd, bob, bob);

        // console.log(adapter.totalAssets());
        // console.log(wstETH.balanceOf(address(adapter)));
        // console.log(IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).balanceOf(address(adapter)));
        // console.log(address(adapter).balance);

        // withdraw dust from owner
        uint256 dust = address(adapter).balance;
        uint256 aliceBalBefore = alice.balance;

        adapterContract.withdrawDust(alice);

        assertEq(alice.balance, aliceBalBefore + dust);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(wstETH), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat("VaultCraft Leveraged ", IERC20Metadata(address(asset)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(asset.allowance(address(adapter), address(lendingPool)), type(uint256).max, "allowance");
    }
}
