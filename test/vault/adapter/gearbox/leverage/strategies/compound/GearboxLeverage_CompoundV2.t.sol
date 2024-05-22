// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {GearboxLeverage, IERC20, IERC20Metadata} from "../../../../../../../src/vault/adapter/gearbox/leverage/GearboxLeverage.sol";
import {GearboxLeverageTestConfigStorage, GearboxLeverageTestConfig} from "../../GearboxLeverageTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../../../abstract/AbstractAdapterTest.sol";
import {GearboxLeverage_CompoundV2} from "../../../../../../../src/vault/adapter/gearbox/leverage/strategies/compound/GearboxLeverage_CompoundV2.sol";

interface ILeverageAdapter is IAdapter {
    function adjustLeverage(uint256 amount, bytes memory data) external;
}


contract GearboxLeverage_CompoundV2_Test is AbstractAdapterTest {

    //IERC20 _asset;
    address USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address addressProvider = 0xcF64698AFF7E5f27A11dff868AF228653ba53be0;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 19923553);
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
        (address _creditFacade, address _creditManager, address _strategyAdapter) = abi.decode(testConfig, (address, address, address));

        setUpBaseTest(
            IERC20(DAI),
            address(new GearboxLeverage_CompoundV2()),
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
    }

    /*//////////////////////////////////////////////////////////////
                          TOTAL ASSETS
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
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
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/
    function test__maxDeposit() public override {
        prop_maxDeposit(bob);

        // Deposit smth so withdraw on pause is not 0
        _mintAsset(defaultAmount, address(this));
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, address(this));

        adapter.pause();
        assertEq(adapter.maxDeposit(bob), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ADJUST LEVERAGE
    //////////////////////////////////////////////////////////////*/
    function test__adjustLeverage() public {
        _mintAsset(defaultAmount, bob);
        vm.prank(bob);
        asset.approve(address(adapter), defaultAmount);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        bytes memory data = abi.encode(address(asset), defaultAmount);
        ILeverageAdapter(address(adapter)).adjustLeverage(1, data);
    }


    function test__harvest() public override {}

    function test__redeem(uint8 fuzzAmount) public override {}
    function test__RT_mint_redeem() public override {}
    function test__RT_deposit_redeem() public override {}
    function test__previewRedeem(uint8 fuzzAmount) public override {}
}
