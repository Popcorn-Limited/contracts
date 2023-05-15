// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {CurveGaugeAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, IMinter, IGaugeController, IWithRewards, IStrategy} from "../../../../../../src/vault/adapter/curve/gauge/mainnet/CurveGaugeAdapter.sol";
import {CurveGaugeTestConfigStorage, CurveGaugeTestConfig} from "./CurveGaugeTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../../utils/mocks/MockStrategyClaimer.sol";

contract CurveGaugeAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    address crv;
    IMinter minter = IMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    IGauge gauge;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new CurveGaugeTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        uint256 _gaugeId = abi.decode(testConfig, (uint256));

        gauge = IGauge(IGaugeController(minter.controller()).gauges(_gaugeId));
        asset = IERC20(gauge.lp_token());
        crv = minter.token();

        setUpBaseTest(
            IERC20(asset),
            address(new CurveGaugeAdapter()),
            address(minter),
            10,
            "Curve",
            true
        );

        vm.label(address(crv), "CRV");
        vm.label(address(minter), "minter");
        vm.label(address(gauge), "gauge");
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

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft CurveGauge ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcCrvG-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(gauge)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__claim() public override {
        strategy = IStrategy(address(new MockStrategyClaimer()));
        createAdapter();
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfigStorage.getTestConfig(0)
        );

        _mintAssetAndApproveForAdapter(1000e18, bob);

        vm.prank(bob);
        adapter.deposit(1000e18, bob);

        vm.warp(block.timestamp + 30 days);

        vm.prank(bob);
        adapter.withdraw(1, bob, bob);

        address[] memory rewardTokens = IWithRewards(address(adapter))
            .rewardTokens();
        assertEq(rewardTokens[0], 0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV

        assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
    }
}
