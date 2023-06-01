// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {MetaPoolAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IMetaPool} from "../../../../src/vault/adapter/metapool/MetaPoolAdapter.sol";
import {MetaPoolTestConfigStorage, MetaPoolTestConfig} from "./MetaPoolTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract MetaPoolAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IMetaPool public iPool;

    address poolAddress;

    IERC20Metadata public stNear;
    IERC20Metadata public wNear;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("aurora"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new MetaPoolTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        poolAddress = abi.decode(testConfig, (address));
        iPool = IMetaPool(poolAddress);

        wNear = iPool.wNear();
        stNear = iPool.stNear();

        setUpBaseTest(
            IERC20(wNear),
            address(new MetaPoolAdapter()),
            poolAddress,
            10,
            "popE-",
            true
        );

        vm.label(address(asset), "wNear");
        vm.label(address(poolAddress), "poolAddress");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(address(wNear), address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        defaultAmount = adapter.maxDeposit(address(this)) / 10;
        maxAssets = defaultAmount / 1000;
        minFuzz = defaultAmount / 10000;
        maxShares = maxAssets / 5;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
  //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(stNear),
            address(adapter),
            IERC20(address(asset)).balanceOf(address(adapter)) + amount
        );
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isn't 0
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
                          INITIALIZATION
  //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        testConfigStorage = ITestConfigStorage(
            address(new MetaPoolTestConfigStorage())
        );

        createAdapter();
        uint256 callTime = block.timestamp;

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(IERC20(wNear), address(this), strategy, 0, sigs, ""),
            externalRegistry,
            ""
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

    function verify_adapterInit() public override {
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft MetaPool ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcM-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), poolAddress),
            type(uint256).max,
            "allowance"
        );

        assertEq(
            IERC20(wNear).allowance(address(adapter), poolAddress),
            type(uint256).max,
            "allowance"
        );
    }
}
