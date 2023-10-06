//// SPDX-License-Identifier: GPL-3.0
//pragma solidity ^0.8.15;
//
//import {Test} from "forge-std/Test.sol";
//
//import {OriginAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IStrategy, IAdapter, IERC4626} from "../../../../src/vault/adapter/origin/OriginAdapter.sol";
//import {OriginTestConfigStorage, OriginTestConfig} from "./OriginTestConfigStorage.sol";
//import {AbstractAdapterTest, ITestConfigStorage} from "../abstract/AbstractAdapterTest.sol";
//import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
//import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";
//
//contract OriginAdapterTest is AbstractAdapterTest {
//    using Math for uint256;
//
//    IERC4626 public wAsset;
//    address assetWhale;
//
//    IPermissionRegistry permissionRegistry;
//
//    function setUp() public {
//        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
//        vm.selectFork(forkId);
//
//        testConfigStorage = ITestConfigStorage(
//            address(new OriginTestConfigStorage())
//        );
//
//        _setUpTest(testConfigStorage.getTestConfig(0));
//    }
//
//    function overrideSetup(bytes memory testConfig) public override {
//        _setUpTest(testConfig);
//    }
//
//    function _setUpTest(bytes memory testConfig) internal {
//        (
//            address _wAsset,
//            uint256 _defaultAmount,
//            uint256 _raise,
//            uint256 _maxAssets,
//            uint256 _maxShares,
//            address _assetWhale
//        ) = abi.decode(
//                testConfig,
//                (address, uint256, uint256, uint256, uint256, address)
//            );
//
//        wAsset = IERC4626(_wAsset);
//        asset = IERC20(wAsset.asset());
//
//        permissionRegistry = IPermissionRegistry(
//            address(new PermissionRegistry(address(this)))
//        );
//        setPermission(_wAsset, true, false);
//
//        setUpBaseTest(
//            IERC20(asset),
//            address(new OriginAdapter()),
//            address(permissionRegistry),
//            10,
//            "Ousd",
//            true
//        );
//
//        vm.label(address(wAsset), "wAsset");
//        vm.label(address(asset), "asset");
//        vm.label(address(this), "test");
//
//        adapter.initialize(
//            abi.encode(asset, address(this), strategy, 0, sigs, ""),
//            externalRegistry,
//            abi.encode(_wAsset)
//        );
//
//        defaultAmount = _defaultAmount;
//        raise = _raise;
//        maxAssets = _maxAssets;
//        maxShares = _maxShares;
//
//        assetWhale = _assetWhale;
//    }
//
//    /*//////////////////////////////////////////////////////////////
//                          HELPER
//    //////////////////////////////////////////////////////////////*/
//
//    function _mintAsset(uint256 amount, address receiver) internal override {
//        vm.prank(assetWhale);
//        IERC20(asset).transfer(receiver, amount + 1);
//    }
//
//    function increasePricePerShare(uint256 amount) public override {
//        vm.startPrank(assetWhale);
//        IERC20(asset).approve(address(wAsset), 0);
//        IERC20(asset).approve(address(wAsset), amount);
//
//        wAsset.deposit(amount, address(adapter));
//        vm.stopPrank();
//    }
//
//    // Verify that totalAssets returns the expected amount
//    function verify_totalAssets() public override {
//        _mintAsset(defaultAmount, bob);
//        vm.startPrank(bob);
//        asset.approve(address(adapter), defaultAmount);
//        adapter.deposit(defaultAmount, bob);
//        vm.stopPrank();
//
//        assertEq(
//            adapter.totalAssets(),
//            adapter.convertToAssets(adapter.totalSupply()),
//            string.concat("totalSupply converted != totalAssets", baseTestId)
//        );
//    }
//
//    function setPermission(
//        address target,
//        bool endorsed,
//        bool rejected
//    ) public {
//        address[] memory targets = new address[](1);
//        Permission[] memory permissions = new Permission[](1);
//        targets[0] = target;
//        permissions[0] = Permission(endorsed, rejected);
//        permissionRegistry.setPermissions(targets, permissions);
//    }
//
//    /*//////////////////////////////////////////////////////////////
//                          INITIALIZATION
//    //////////////////////////////////////////////////////////////*/
//
//    function test__initialization() public override {
//        createAdapter();
//        uint256 callTime = block.timestamp;
//
//        (
//            address _wAsset,
//            uint256 _defaultAmount,
//            uint256 _raise,
//            uint256 _maxAssets,
//            uint256 _maxShares,
//            address _assetWhale
//        ) = abi.decode(
//                testConfigStorage.getTestConfig(0),
//                (address, uint256, uint256, uint256, uint256, address)
//            );
//
//        vm.expectEmit(false, false, false, true, address(adapter));
//        emit Initialized(uint8(1));
//
//        adapter.initialize(
//            abi.encode(asset, address(this), strategy, 0, sigs, ""),
//            externalRegistry,
//            abi.encode(_wAsset)
//        );
//
//        assertEq(adapter.owner(), address(this), "owner");
//        assertEq(adapter.strategy(), address(strategy), "strategy");
//        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
//        assertEq(adapter.strategyConfig(), "", "strategyConfig");
//        assertEq(
//            IERC20Metadata(address(adapter)).decimals(),
//            IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
//            "decimals"
//        );
//
//        verify_adapterInit();
//    }
//
//    function verify_adapterInit() public override {
//        assertEq(adapter.asset(), address(asset), "asset");
//        assertEq(
//            IERC20Metadata(address(adapter)).name(),
//            string.concat(
//                "VaultCraft Origin ",
//                IERC20Metadata(address(asset)).name(),
//                " Adapter"
//            ),
//            "name"
//        );
//        assertEq(
//            IERC20Metadata(address(adapter)).symbol(),
//            string.concat("vcO-", IERC20Metadata(address(asset)).symbol()),
//            "symbol"
//        );
//
//        assertEq(
//            asset.allowance(address(adapter), address(wAsset)),
//            type(uint256).max,
//            "allowance"
//        );
//    }
//}
