// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {LidoAdapter, SafeERC20, IERC20, Math, IERC20Metadata, ILido} from "../../../../src/vault/adapter/lido/LidoAdapter.sol";
import {LidoTestConfigStorage, LidoTestConfig} from "./LidoTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../abstract/AbstractAdapterTest.sol";

contract LidoAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new LidoTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        setUpBaseTest(
            IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // Weth
            address(new LidoAdapter()),
            address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84), // stEth
            10,
            "Lido ",
            true
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        defaultAmount = 1 ether;
        raise = 100 ether;
        maxAssets = 10 ether;
        maxShares = 10e27;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(address(adapter), 100 ether);
        vm.prank(address(adapter));
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{
            value: 100 ether
        }(address(0));
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        _mintAsset(defaultAmount, bob);
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
            "VaultCraft stEth Adapter",
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            "vcStEth",
            "symbol"
        );

        // assertEq(
        //     IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).allowance(address(adapter), address(wAsset)),
        //     type(uint256).max,
        //     "allowance"
        // );
    }
}
