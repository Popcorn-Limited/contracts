// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import { CurveLPAdapter, IERC20, Math } from "../../../../src/vault/adapter/curve/CurveLPAdapter.sol";
import { CurveLPTestConfigStorage, CurveLPTestConfig } from "./CurveLPTestConfigStorage.sol";
import { AbstractAdapterTest, ITestConfigStorage, IAdapter } from "../abstract/AbstractAdapterTest.sol";

contract CurveLPAdapterTest is AbstractAdapterTest {
    using Math for uint;    

    function setUp() public {
        uint forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new CurveLPTestConfigStorage())
        );

        asset = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    
        setUpBaseTest(
            IERC20(asset),
            address(new CurveLPAdapter()),
            0x46a8a9CF4Fc8e99EC3A14558ACABC1D93A27de68,
            1e12, // delta is large because the pool tkaes fees with every deposit/withdrawal
            "Curve",
            true
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfigStorage.getTestConfig(0)
        );
    
        vm.label(address(adapter), "adapter");
        vm.label(address(this), "test");
        vm.label(address(asset), "USDC");
        vm.label(bob, "bob");
    }

    function increasePricePerShare(uint256 amount) public override {
        IERC20 poolToken = CurveLPAdapter(address(adapter)).poolToken();
        deal(address(poolToken), address(adapter), poolToken.balanceOf(address(adapter)) + amount * 1e9);
      }

    function test_totalAssets() public {
        uint amount = 1_000e6;
        deal(address(asset), bob, amount);
        vm.startPrank(bob);
        asset.approve(address(adapter), amount);
        adapter.deposit(amount, bob);
        vm.stopPrank();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    function test_fullRedeem() public {
        uint amount = 1_000e6;
        deal(address(asset), bob, amount);
        vm.startPrank(bob);
        asset.approve(address(adapter), amount);
        adapter.deposit(amount, bob);
        vm.stopPrank();

        uint totalAssets = adapter.totalAssets();
        uint preBalance = asset.balanceOf(bob);
        vm.startPrank(bob);
        adapter.redeem(adapter.balanceOf(bob), bob, bob);
        vm.stopPrank();

        assertEq(
            asset.balanceOf(bob) - preBalance,
            totalAssets,
            "redeeming total supply of shares doesn't match totalAssets()"
        );
    }
}