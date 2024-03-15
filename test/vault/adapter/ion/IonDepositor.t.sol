// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IonDepositor, SafeERC20, IERC20, IERC20Metadata, Math} from "../../../../src/vault/adapter/ion/IonDepositor.sol";
import {IIonPool, IWhitelist} from "../../../../src/vault/adapter/ion/IIonProtocol.sol";
import {IonDepositorTestConfigStorage, IonDepositorTestConfig} from "./IonDepositorTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract IonDepositorTest is AbstractAdapterTest {
    using Math for uint256;

    IIonPool public ionPool;
    IWhitelist public whitelist;

    address public ionOwner;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new IonDepositorTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (
            address _asset,
            address _ionPool,
            address _whitelist,
            address _ionOwner
        ) = abi.decode(testConfig, (address, address, address, address));

        ionPool = IIonPool(_ionPool);
        whitelist = IWhitelist(_whitelist);
        ionOwner = _ionOwner;

        // remove whitelist proof requirement
        vm.startPrank(ionOwner);
        whitelist.updateLendersRoot(0);
        ionPool.updateSupplyCap(100000e18);
        vm.stopPrank();

        setUpBaseTest(
            IERC20(_asset),
            address(new IonDepositor()),
            address(0),
            10,
            "Ion ",
            true
        );

        vm.label(address(ionPool), "IonPool");
        vm.label(address(_asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(_asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_ionPool)
        );

        defaultAmount = 10 ** IERC20Metadata(address(_asset)).decimals();

        raise = defaultAmount;
        maxAssets = defaultAmount * 1000;
        minShares = minFuzz;
        maxShares = maxAssets / 2;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(asset),
            address(ionPool),
            asset.balanceOf(address(ionPool)) + amount
        );
    }

    function iouBalance() public view override returns (uint256) {
        return ionPool.balanceOf(address(adapter));
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
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        (
            address _asset,
            address _ionPool,
            address _whitelist,
            address _ionOwner
        ) = abi.decode(
                testConfigStorage.getTestConfig(0),
                (address, address, address, address)
            );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_ionPool)
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
        assertEq(adapter.asset(), ionPool.underlying(), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft IonDepositor ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-ion-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(ionPool)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {}
}
