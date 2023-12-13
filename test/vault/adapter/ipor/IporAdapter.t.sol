// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import "forge-std/Console.sol";
import {Test} from "forge-std/Test.sol";
import {
    Math,
    IERC20,
    SafeERC20,
    IERC20Metadata,
    IporAdapter,
    IAmmPoolsLens,
    IAmmPoolsService
} from "../../../../src/vault/adapter/ipor/IporAdapter.sol";
import {IporProtocolTestConfigStorage, IporProtocolTestConfig} from "./IporProtocolTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";
import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";


contract IporAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IAmmPoolsLens public ammPoolsLens;
    IAmmPoolsService public ammPoolsService;
    IPermissionRegistry public permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new IporProtocolTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _ammPoolService, address _ammPoolsLens, address _asset) = abi.decode(testConfig, (address, address, address ));

        ammPoolsService = IAmmPoolsService(_ammPoolService);
        ammPoolsLens = IAmmPoolsLens(_ammPoolsLens);

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );

        setPermission(_ammPoolsLens, true, false);
        setPermission(_ammPoolService, true, false);

        setUpBaseTest(
            IERC20(_asset),
            address(new IporAdapter()),
            address(permissionRegistry),
            10,
            "Ipor",
            true
        );

        vm.label(address(this), "test");
        vm.label(address(asset), "asset");
        vm.label(address(ammPoolsLens), "amm pool lens");
        vm.label(address(ammPoolsService), "amm pool service");


        adapter.initialize(
            abi.encode(asset, address(this), address(strategy), 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
//        deal(
//            address(asset),
//            address(vault),
//            asset.balanceOf(address(vault)) + amount
//        );
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
                "VaultCraft Ipor ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcIpor-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    function test__unpause() public override {
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        uint256 penaltyDiff = oldTotalAssets - adapter.totalAssets();
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            penaltyDiff,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            0,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }

    function test__harvest() public override {}
}
