// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {CurveLPAdapter, IERC20, IERC20Metadata, Math} from "../../../../src/vault/adapter/curve/CurveLPAdapter.sol";
import {CurveLPTestConfigStorage, CurveLPTestConfig} from "./CurveLPTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract CurveLPAdapterTest is AbstractAdapterTest {
    using Math for uint;

    function setUp() public {
        uint forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new CurveLPTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, uint _pId) = abi.decode(testConfig, (address, uint));

        setUpBaseTest(
            IERC20(_asset),
            address(new CurveLPAdapter()),
            0x46a8a9CF4Fc8e99EC3A14558ACABC1D93A27de68,
            10, // delta is large because the pool takes fees with every deposit/withdrawal
            "Curve",
            false
        );

        adapter.initialize(
            abi.encode(_asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_pId)
        );

        vm.label(address(adapter), "adapter");
        vm.label(address(this), "test");
        vm.label(address(_asset), "asset");
        vm.label(bob, "bob");
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        IERC20 poolToken = CurveLPAdapter(address(adapter)).poolToken();
        deal(
            address(poolToken),
            address(adapter),
            poolToken.balanceOf(address(adapter)) + amount * 1e9
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        (address _asset, uint _pId) = abi.decode(
            testConfigStorage.getTestConfig(0),
            (address, uint)
        );

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_pId)
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

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
        deal(address(asset), bob, defaultAmount);
        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          OTHER
    //////////////////////////////////////////////////////////////*/

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
