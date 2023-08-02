// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import "../abstract/AbstractAdapterTest.sol";
import "./GmxTestConfigStorage.sol";
import {GmxAdapter, IRewardTracker, IRewardRouterV2} from "../../../../src/vault/adapter/gmx/GmxAdapter.sol";

contract GmxAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IRewardRouterV2 private router;
    IRewardTracker private rewardTracker;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new GmxTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));

        defaultAmount = 1e18;

        minFuzz = 1e18;
        minShares = 1e27;

        raise = defaultAmount * 1_000;

        maxAssets = minFuzz * 10;
        maxShares = minShares * 10;
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {

        setUpBaseTest(
            IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a), // GMX
            address(new GmxAdapter()),
            0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1,
            10,
            "GMX ",
            false
        );

        router = IRewardRouterV2(externalRegistry);

        rewardTracker = IRewardTracker(router.stakedGmxTracker());

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    function createAdapter() public override {
        adapter = IAdapter(Clones.clone(address(new GmxAdapter())));
        vm.label(address(adapter), "adapter");
    }

    function test__deposit(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));
            uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

            emit log_named_uint("balance bob", asset.balanceOf(bob));

            _mintAssetAndApproveForAdapter(amount, bob);

            emit log_named_uint("balance bob", asset.balanceOf(bob));
            emit log("PING");

            prop_deposit(bob, bob, amount, testId);
            emit log("PING1");

            increasePricePerShare(raise);

            _mintAssetAndApproveForAdapter(amount, bob);
            prop_deposit(bob, alice, amount, testId);
        }
    }
}
