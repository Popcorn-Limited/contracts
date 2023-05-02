// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {AlpacaLendV1Adapter, SafeERC20, IERC20, IERC20Metadata, Math, IAlpacaLendV1Vault, IStrategy, IAdapter, IWithRewards} from "../../../../../src/vault/adapter/alpaca/alpacaLendV1/AlpacaLendV1Adapter.sol";
import {AlpacaLendV1TestConfigStorage, AlpacaLendV1TestConfig} from "./AlpacaLendV1TestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract AlpacaLendV1AdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IAlpacaLendV1Vault public alpacaVault;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("bnb_smart_chain"));
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

        setUpBaseTest(
            IERC20(alpacaVault.token()),
            address(new AlpacaLendV1Adapter()),
            address(alpacaVault),
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
                              CLAIM
    //////////////////////////////////////////////////////////////*/

    // function test__claim() public override {
    //     strategy = IStrategy(address(new MockStrategyClaimer()));
    //     createAdapter();
    //     adapter.initialize(
    //         abi.encode(asset, address(this), strategy, 0, sigs, ""),
    //         externalRegistry,
    //         testConfigStorage.getTestConfig(0)
    //     );

    //     _mintAssetAndApproveForAdapter(1000e18, bob);

    //     vm.prank(bob);
    //     adapter.deposit(1000e18, bob);

    //     vm.roll(block.number + 30);
    //     vm.warp(block.timestamp + 2);

    //     vm.prank(bob);
    //     adapter.withdraw(0, bob, bob);

    //     address[] memory rewardTokens = IWithRewards(address(adapter))
    //         .rewardTokens();
    //     assertEq(rewardTokens[0], rewardsToken);

    //     assertGt(
    //         IERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2).balanceOf(
    //             address(adapter)
    //         ),
    //         0
    //     );
    // }
}
