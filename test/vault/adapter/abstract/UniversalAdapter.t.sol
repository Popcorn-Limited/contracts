// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "forge-std/StdCheats.sol";

import {SafeERC20, IERC20, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy} from "../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "../convex/ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter, IERC20} from "./AbstractAdapterTest.sol";
import {UniversalAdapter} from "../../../../src/vault/adapter/abstracts/UniversalAdapter.sol";

contract UniversalAdapterTest is AbstractAdapterTest {
    UniversalAdapter adapterContract;
    uint256 pid = 62;
    IConvexBooster convexBooster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IConvexRewards convexRewards;

    uint256 mintAmount = 10;
    uint256 depositAmount = 4;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 18798175);

        _setUpTest();
    }

    function overrideSetup(bytes memory) public override {
        _setUpTest();
    }

    function _setUpTest() internal {
        (address _asset, , , address _convexRewards, , ) = convexBooster
            .poolInfo(pid);

        convexRewards = IConvexRewards(_convexRewards);

        setUpBaseTest(
            IERC20(_asset),
            address(new UniversalAdapter()),
            address(0),
            10,
            "Universal",
            true
        );

        adapterContract = UniversalAdapter(address(adapter));

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(0)
        );

        // TODO 
        vm.prank(address(adapter));
        asset.approve(address(convexBooster), type(uint256).max);

        // add deposit calldata 
        _setup_depositData();

        // add total assets calldata 
        _setup_totalAssetsData();

        // add withdraw calldata
        _setup_withdrawData();
    }

    function test_deposit_execute() public {
        // mint assets to bob 
        deal(address(asset), address(bob), mintAmount);

        uint256 assetBalanceBefore = asset.balanceOf(bob);
        uint256 sharesBalanceBefore = adapter.balanceOf(bob);
        uint256 adapterBalanceBefore = asset.balanceOf(address(adapter));

        _deposit();

        uint256 assetBalanceAfter = asset.balanceOf(bob);
        uint256 sharesBalanceAfter = adapter.balanceOf(bob);
        uint256 adapterBalanceAfter = asset.balanceOf(address(adapter));

        assertEq(assetBalanceAfter, assetBalanceBefore - depositAmount);  
        assertEq(adapterBalanceBefore, adapterBalanceAfter);
        assertGt(sharesBalanceAfter, sharesBalanceBefore);
    }

    function test_totalAssets_execute() public {
        // mint assets to bob 
        deal(address(asset), address(bob), mintAmount);

        _deposit();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    function test_withdraw_execute() public {
        // mint assets to bob and deposit
        deal(address(asset), address(bob), mintAmount);
        _deposit();

        uint256 assetBalanceBefore = asset.balanceOf(bob);
        uint256 sharesBalanceBefore = adapter.balanceOf(bob);
        uint256 adapterBalanceBefore = asset.balanceOf(address(adapter));

        uint256 withdrawAmount = adapter.convertToAssets(sharesBalanceBefore / 2);
        uint256 expectedSharesOut = sharesBalanceBefore / 2;

        // withdraw 
        vm.startPrank(bob);
        adapter.withdraw(withdrawAmount, bob, bob);
        vm.stopPrank();

        uint256 assetBalanceAfter = asset.balanceOf(bob);
        uint256 sharesBalanceAfter = adapter.balanceOf(bob);
        uint256 adapterBalanceAfter = asset.balanceOf(address(adapter));

        assertEq(assetBalanceAfter, assetBalanceBefore + withdrawAmount);
        assertEq(sharesBalanceAfter, sharesBalanceBefore - expectedSharesOut);
        assertEq(adapterBalanceAfter, adapterBalanceBefore);
    }

    function _setup_depositData() internal {
        //adding convexBooster.deposit(pid, amount, true);
        bytes[] memory calldataParams = new bytes[](3);
        bytes4 sig = bytes4(keccak256(abi.encodePacked("deposit(uint256,uint256,bool)")));
        calldataParams[0] = abi.encode(pid); // fixed param
        calldataParams[1] = abi.encode(0); // dynamic param
        calldataParams[2] = abi.encode(true); // fixed param

        UniversalAdapter.DynamicParam[] memory dynamicParams = new UniversalAdapter.DynamicParam[](1);
        dynamicParams[0].slotPosition = 1; // index in the calldataParams to update
        
        adapterContract.setProtocolData(0, sig, calldataParams, address(convexBooster), dynamicParams);
    }

    function _deposit() internal {
        vm.startPrank(bob);
        asset.approve(address(adapter), depositAmount);
        adapter.deposit(depositAmount, bob);
        vm.stopPrank();
    }

    function _setup_totalAssetsData() internal {
         //adding convexRewards.balanceOf(address(this));
        bytes[] memory calldataParams = new bytes[](1);
        bytes4 sig = bytes4(keccak256(abi.encodePacked("balanceOf(address)")));
        calldataParams[0] = abi.encode(0); // dynamic param

        UniversalAdapter.DynamicParam[] memory dynamicParams = new UniversalAdapter.DynamicParam[](1);
        dynamicParams[0].slotPosition = 0; // index in the calldataParams to update
        
        adapterContract.setProtocolData(1, sig, calldataParams, address(convexRewards), dynamicParams);
    }

    function _setup_withdrawData() internal {
        //adding convexRewards.withdrawAndUnwrap(amount, false);
        bytes[] memory calldataParams = new bytes[](2);
        bytes4 sig = bytes4(keccak256(abi.encodePacked("withdrawAndUnwrap(uint256,bool)")));
        
        calldataParams[0] = abi.encode(0); // dynamic param
        calldataParams[1] = abi.encode(false);

        UniversalAdapter.DynamicParam[] memory dynamicParams = new UniversalAdapter.DynamicParam[](1);
        dynamicParams[0].slotPosition = 0; // index in the calldataParams to update
        
        adapterContract.setProtocolData(2, sig, calldataParams, address(convexRewards), dynamicParams);
    }

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Convex ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcCvx-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(convexBooster)),
            type(uint256).max,
            "allowance"
        );
    }
}
