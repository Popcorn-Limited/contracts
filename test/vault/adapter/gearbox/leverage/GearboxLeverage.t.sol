// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {GearboxLeverage, IERC20, IERC20Metadata} from "../../../../../src/vault/adapter/gearbox/leverage/GearboxLeverage.sol";
import {GearboxLeverageTestConfigStorage, GearboxLeverageTestConfig} from "./GearboxLeverageTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../abstract/AbstractAdapterTest.sol";


contract GearboxLeverageTest is AbstractAdapterTest {
    //IERC20 _asset;
    address USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address addressProvider = 0xcF64698AFF7E5f27A11dff868AF228653ba53be0;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new GearboxLeverageTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _creditFacade, address _creditManager) = abi.decode(testConfig, (address, address));

        setUpBaseTest(
            IERC20(USDC),
            address(new GearboxLeverage()),
            addressProvider,
            10,
            "Gearbox Leverage ",
            false
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        defaultAmount = 10 ** IERC20Metadata(address(asset)).decimals();

        raise = defaultAmount;
        maxAssets = defaultAmount * 1000;
        maxShares = maxAssets / 2;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/



    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
//        assertEq(adapter.asset(), poolService.underlyingToken(), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft GearboxLeverage ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-gl-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

//        assertEq(
//            asset.allowance(address(adapter), address(poolService)),
//            type(uint256).max,
//            "allowance"
//        );
    }

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
        _mintAsset(defaultAmount, bob);

        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertApproxEqAbs(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            _delta_,
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );

//        assertApproxEqAbs(
//            adapter.totalAssets(),
//            poolService.fromDiesel(iouBalance()),
//            _delta_,
//            string.concat("totalAssets != pool assets", baseTestId)
//        );
    }
}
