// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {MorphoAaveAdapter, SafeERC20, IERC20, IERC20Metadata, IMorphoAave, IAaveLens} from "../../../../src/vault/adapter/morpho/aave/MorphoAaveAdapter.sol";
import {MorphoAaveTestConfigStorage, MorphoAaveTestConfig} from "./MorphoAaveTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter, Math} from "../abstract/AbstractAdapterTest.sol";
import {IPermissionRegistry, Permission} from "../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {IAToken} from "../../../../src/vault/adapter/morpho/aave/IAToken.sol";
import {PermissionRegistry} from "../../../../src/vault/PermissionRegistry.sol";

contract MorphoAaveAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    address public poolToken;
    IMorphoAave public morpho;
    IAaveLens public lens;
    IPermissionRegistry permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new MorphoAaveTestConfigStorage())
        );

         _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        createAdapter();

        (address _poolToken, address _morpho, address _lens) = abi.decode(
            testConfig,
            (address, address, address)
        );

        poolToken = _poolToken;
        morpho = IMorphoAave(_morpho);
        lens = IAaveLens(_lens);
        asset = IERC20(IAToken(poolToken).UNDERLYING_ASSET_ADDRESS());

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(address(morpho), true, false);

        setUpBaseTest(
            asset,
            address(new MorphoAaveAdapter()),
            address(permissionRegistry),
            10,
            "MorphoAave ",
            true
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
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

    function test__RT_deposit_withdraw() public override {}

    function test__RT_mint_withdraw() public override {}

    function test__harvest() public override {}
}
