// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IchiAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IVault, IVaultFactory, IDepositGuard, IStrategy, IAdapter, IWithRewards} from "../../../../src/vault/adapter/ichi/IchiAdapter.sol";
import {IchiTestConfigStorage, IchiTestConfig} from "./IchiTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";

contract IchiAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    address public ichi;
    IVault public vault;
    IDepositGuard public depositGuard;
    IVaultFactory public vaultFactory;
    address public vaultDeployer;
    uint256 public pid;
    uint8 public assetIndex;
    address public uniRouter;
    uint24 public swapFee;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new IchiTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (
            uint256 _pid,
            address _depositGuard,
            address _vaultDeployer,
            address _uniRouter,
            uint24 _swapFee
        ) = abi.decode(
                testConfig,
                (uint256, address, address, address, uint24)
            );

        pid = _pid;
        vaultDeployer = _vaultDeployer;
        uniRouter = _uniRouter;
        swapFee = _swapFee;

        depositGuard = IDepositGuard(_depositGuard);
        vaultFactory = IVaultFactory(depositGuard.ICHIVaultFactory());
        vault = IVault(vaultFactory.allVaults(pid));

        assetIndex = vault.token0() == address(asset) ? 0 : 1;
        asset = assetIndex == 0
            ? IERC20(vault.token0())
            : IERC20(vault.token1());
        ichi = assetIndex == 0 ? vault.token0() : vault.token1();

        setUpBaseTest(
            IERC20(asset),
            address(new IchiAdapter()),
            address(vaultFactory),
            10,
            "Ichi",
            true
        );

        vm.label(address(vaultFactory), "Vault Factory");
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

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Ichi ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcIchi-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(depositGuard)),
            type(uint256).max,
            "allowance"
        );
    }
}
