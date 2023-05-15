// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {SolidlyAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, ILpToken} from "../../../../src/vault/adapter/solidly/SolidlyAdapter.sol";
import {SolidlyTestConfigStorage, SolidlyTestConfig} from "./SolidlyTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";

contract SolidlyAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IGauge gauge;
    ILpToken lpToken;
    address solid;
    IPermissionRegistry permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new SolidlyTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _gauge = abi.decode(testConfig, (address));

        IGauge gauge = IGauge(_gauge);
        ILpToken lpToken = ILpToken(gauge.stake());
        address solid = gauge.solid();
        asset = IERC20(address(lpToken));

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(_gauge, true, false);

        setUpBaseTest(
            IERC20(asset),
            address(new SolidlyAdapter()),
            address(permissionRegistry),
            10,
            "Solidly",
            true
        );

        vm.label(address(solid), "SOLID");
        vm.label(address(gauge), "gauge");
        vm.label(address(lpToken), "lpToken");
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
            address(gauge),
            asset.balanceOf(address(gauge)) + amount
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
                "VaultCraft Solidly ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcSld-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }
}
