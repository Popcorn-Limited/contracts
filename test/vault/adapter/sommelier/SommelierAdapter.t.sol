// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {SommelierAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IVault} from "../../../../src/vault/adapter/sommelier/SommelierAdapter.sol";
import {SommelierTestConfigStorage, SommelierTestConfig} from "./SommelierTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";

contract SommelierAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IVault vault;
    IPermissionRegistry permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new SommelierTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _vault = abi.decode(testConfig, (address));

        vault = IVault(_vault);
        asset = IERC20(address(vault.asset()));

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(_vault, true, false);

        setUpBaseTest(
            IERC20(asset),
            address(new SommelierAdapter()),
            address(permissionRegistry),
            10,
            "Sommelier",
            true
        );

        vm.label(address(vault), "vault");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(asset),
            address(vault),
            asset.balanceOf(address(vault)) + amount
        );
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

    function setPermission(
        address target,
        bool endorsed,
        bool rejected
    ) public {
        address[] memory targets = new address[](1);
        Permission[] memory permissions = new Permission[](1);
        targets[0] = target;
        permissions[0] = Permission(endorsed, rejected);
        permissionRegistry.setPermissions(targets, permissions);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Sommelier ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcSomm-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    // function test__RT_deposit_withdraw() public override {
    //     _mintAssetAndApproveForAdapter(defaultAmount, bob);

    //     vm.startPrank(bob);
    //     uint256 shares1 = adapter.deposit(defaultAmount, bob);

    //     vm.warp(block.timestamp + 1200000);

    //     uint256 shares2 = adapter.withdraw(adapter.maxWithdraw(bob), bob, bob);
    //     vm.stopPrank();

    //     // Pass the test if maxWithdraw is smaller than deposit since round trips are impossible
    //     if (adapter.maxWithdraw(bob) == defaultAmount) {
    //         assertGe(shares2, shares1, testId);
    //     }
    // }
}
