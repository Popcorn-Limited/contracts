// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {StakedNearAdapter, IAuroraStNear, SafeERC20, IERC20, IERC20Metadata, Math, IStrategy, IAdapter, IERC4626} from "../../../../../src/vault/adapter/metapool/near/StakedNearAdapter.sol";
import {StakedNearTestConfigStorage, StakedNearTestConfig} from "./StakedNearTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../../abstract/AbstractAdapterTest.sol";

contract StakedNearAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IAuroraStNear public auroraStNear =
        IAuroraStNear(0x534BACf1126f60EA513F796a3377ff432BE62cf9);
    IERC20 public stNear = IERC20(0x07F9F7f963C5cD2BBFFd30CcfB964Be114332E30);

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("aurora"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new StakedNearTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        address _asset = abi.decode(testConfig, (address));

        setUpBaseTest(
            IERC20(_asset),
            address(new StakedNearAdapter()),
            address(auroraStNear),
            10,
            "StNear",
            true
        );

        vm.label(address(auroraStNear), "auroraStNear");
        vm.label(address(_asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(_asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            ""
        );

        defaultAmount = (10 ** 24);
        raise = defaultAmount * 1000;

        minFuzz = (10 ** 24);

        maxAssets = defaultAmount * 10;
        maxShares = maxAssets / 2;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(stNear),
            address(adapter),
            asset.balanceOf(address(adapter)) + amount
        );
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

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

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
            ""
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
                "VaultCraft stNear ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcSt-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(auroraStNear)),
            type(uint256).max,
            "allowance wNear"
        );
        assertEq(
            stNear.allowance(address(adapter), address(auroraStNear)),
            type(uint256).max,
            "allowance stNear"
        );
    }
}
