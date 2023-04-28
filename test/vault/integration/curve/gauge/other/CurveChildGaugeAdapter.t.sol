// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {CurveChildGaugeAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, IGaugeFactory, IWithRewards, IStrategy} from "../../../../../../src/vault/adapter/curve/gauge/other/CurveChildGaugeAdapter.sol";
import {CurveChildGaugeTestConfigStorage, CurveChildGaugeTestConfig} from "./CurveChildGaugeTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../../utils/mocks/MockStrategyClaimer.sol";

contract CurveChildGaugeAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    address crv;
    IGaugeFactory gaugeFactory =
        IGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);
    IGauge gauge;
    uint256 gaugeId;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("polygon"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new CurveChildGaugeTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, address _crv) = abi.decode(
            testConfig,
            (address, address)
        );

        crv = _crv;
        gauge = IGauge(gaugeFactory.get_gauge_from_lp_token(_asset));

        setUpBaseTest(
            IERC20(_asset),
            address(new CurveChildGaugeAdapter()),
            address(gaugeFactory),
            10,
            "Curve",
            true
        );

        vm.label(address(crv), "CRV");
        vm.label(address(gaugeFactory), "gaugeFactory");
        vm.label(address(gauge), "gauge");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_crv)
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

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        (, address _crv) = abi.decode(
            testConfigStorage.getTestConfig(0),
            (address, address)
        );

        if (address(strategy) != address(0)) {
            vm.expectEmit(false, false, false, true, address(strategy));
            emit SelectorsVerified();
            vm.expectEmit(false, false, false, true, address(strategy));
            emit AdapterVerified();
            vm.expectEmit(false, false, false, true, address(strategy));
            emit StrategySetup();
        }
        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_crv)
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
        assertEq(rewardTokens[0], 0x172370d5Cd63279eFa6d502DAB29171933a610AF); // CRV

        assertGt(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
    }
}
