// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {VelodromeCompounder, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, ILpToken, Route} from "../../../../src/vault/adapter/velodrome/VelodromeCompounder.sol";
import {VelodromeCompounderTestConfigStorage} from "./VelodromeCompounderTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";
import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";

contract VelodromeCompounderTest is AbstractAdapterTest {
    using Math for uint256;

    IGauge gauge;
    ILpToken lpToken;
    address velo;
    IPermissionRegistry permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new VelodromeCompounderTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _gauge, address _solidlyRouter) = abi.decode(
            testConfig,
            (address, address)
        );

        IGauge gauge = IGauge(_gauge);
        ILpToken lpToken = ILpToken(gauge.stakingToken());
        address velo = gauge.rewardToken();
        asset = IERC20(address(lpToken));

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(_gauge, true, false);

        setUpBaseTest(
            IERC20(asset),
            address(new VelodromeCompounder()),
            address(permissionRegistry),
            10,
            "Velodrome",
            false
        );

        vm.label(address(velo), "VELO");
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
                "VaultCraft Velodrome ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcVelo-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    Route[][2] routes;
    uint256 minTradeAmount;

    function test__harvest() public override {
        // add VELO -> KUJI route
        routes[0].push(
            Route(
                0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db,
                0x3A18dcC9745eDcD1Ef33ecB93b0b6eBA5671e7Ca,
                false,
                address(0)
            )
        );

        // add VELO -> VELO route
        routes[1].push(
            Route(
                0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db,
                0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db,
                false,
                address(0)
            )
        );

        minTradeAmount = 1e8;

        VelodromeCompounder(address(adapter)).setHarvestValues(
            routes,
            minTradeAmount,
            0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858
        );

        _mintAssetAndApproveForAdapter(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        vm.roll(block.number + 1000_000);
        vm.warp(block.timestamp + 15000_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__harvest_no_rewards() public {
        // add VELO -> KUJI route
        routes[0].push(
            Route(
                0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db,
                0x3A18dcC9745eDcD1Ef33ecB93b0b6eBA5671e7Ca,
                false,
                address(0)
            )
        );

        // add VELO -> VELO route
        routes[1].push(
            Route(
                0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db,
                0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db,
                false,
                address(0)
            )
        );

        VelodromeCompounder(address(adapter)).setHarvestValues(
            routes,
            minTradeAmount,
            0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858
        );

        _mintAssetAndApproveForAdapter(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 150);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }
}
