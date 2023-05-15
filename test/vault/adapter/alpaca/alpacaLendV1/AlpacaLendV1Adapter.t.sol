// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {AlpacaLendV1Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IAlpacaLendV1Vault, IStrategy, IAdapter, IWithRewards} from "../../../../../src/vault/adapter/alpaca/alpacaLendV1/AlpacaLendV1Adapter.sol";
import {AlpacaLendV1TestConfigStorage, AlpacaLendV1TestConfig} from "./AlpacaLendV1TestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";
import {IPermissionRegistry, Permission} from "../../../../../src/interfaces/vault/IPermissionRegistry.sol";
import {PermissionRegistry} from "../../../../../src/vault/PermissionRegistry.sol";

contract AlpacaLendV1AdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IAlpacaLendV1Vault public alpacaVault;
    IPermissionRegistry permissionRegistry;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("binance"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new AlpacaLendV1TestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _alpacaVault = abi.decode(testConfig, (address));

        alpacaVault = IAlpacaLendV1Vault(_alpacaVault);

        permissionRegistry = IPermissionRegistry(
            address(new PermissionRegistry(address(this)))
        );
        setPermission(_alpacaVault, true, false);

        setUpBaseTest(
            IERC20(alpacaVault.token()),
            address(new AlpacaLendV1Adapter()),
            address(permissionRegistry),
            10,
            "AlpacaLendV1",
            true
        );

        vm.label(address(alpacaVault), "AlpacaVault");
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

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
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
                "VaultCraft AlpacaLendV1 ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcAlV1-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(alpacaVault)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public virtual override {
        uint256 performanceFee = 1e16;
        uint256 hwm = 1e9;

        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        adapter.setPerformanceFee(performanceFee);
        increasePricePerShare(raise);

        uint256 gain = ((adapter.convertToAssets(1e18) +
            1 -
            adapter.highWaterMark()) * adapter.totalSupply()) / 1e18;
        uint256 fee = (gain * performanceFee) / 1e18;

        uint256 expectedFee = adapter.convertToShares(fee);

        vm.expectEmit(false, false, false, true, address(adapter));

        emit Harvested();

        adapter.harvest();

        // Multiply with the decimal offset
        assertApproxEqAbs(
            adapter.totalSupply(),
            defaultAmount * 1e9 + expectedFee,
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            adapter.balanceOf(feeRecipient),
            expectedFee,
            _delta_,
            "expectedFee"
        );
    }
}
