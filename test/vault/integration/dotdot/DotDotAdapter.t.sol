// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {DotDotAdapter, SafeERC20, IERC20, IERC20Metadata, IDotDotStaking, IWithRewards, IStrategy} from "../../../../src/vault/adapter/dotdot/DotDotAdapter.sol";
import {DotDotTestConfigStorage, DotDotTestConfig} from "./DotDotTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter, Math} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";

contract DotDotAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IDotDotStaking public lpStaking =
        IDotDotStaking(0x8189F0afdBf8fE6a9e13c69bA35528ac6abeB1af);

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("binance"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new DotDotTestConfigStorage())
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
            address(new DotDotAdapter()),
            address(lpStaking),
            10,
            "DotDot ",
            true
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            ""
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function iouBalance() public view override returns (uint256) {}

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
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "Vaultcraft DotDot ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcD-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

    // function test__deposit(uint8 fuzzAmount) public override {
    //     testConfigStorage = ITestConfigStorage(
    //         address(new DotDotTestConfigStorage())
    //     );

    //     uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
    //     uint8 len = uint8(testConfigStorage.getTestConfigLength());
    //     for (uint8 i; i < len; i++) {
    //         if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

    //         _mintAssetAndApproveForAdapter(amount, bob);
    //         prop_deposit(bob, bob, amount, testId);

    //         increasePricePerShare(raise);

    //         _mintAssetAndApproveForAdapter(amount, bob);
    //         prop_deposit(bob, alice, amount, testId);
    //     }
    // }

    // function test__mint(uint8 fuzzAmount) public override {
    //     testConfigStorage = ITestConfigStorage(
    //         address(new DotDotTestConfigStorage())
    //     );

    //     uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
    //     uint8 len = uint8(testConfigStorage.getTestConfigLength());
    //     for (uint8 i; i < len; i++) {
    //         if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

    //         _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);
    //         prop_mint(bob, bob, amount, testId);

    //         increasePricePerShare(raise);

    //         _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);
    //         prop_mint(bob, alice, amount, testId);
    //     }
    // }

    // function test__withdraw(uint8 fuzzAmount) public override {
    //     testConfigStorage = ITestConfigStorage(
    //         address(new DotDotTestConfigStorage())
    //     );

    //     uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);
    //     uint8 len = uint8(testConfigStorage.getTestConfigLength());
    //     for (uint8 i; i < len; i++) {
    //         if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

    //         uint256 reqAssets = (adapter.previewMint(
    //             adapter.previewWithdraw(amount)
    //         ) * 10) / 8;
    //         _mintAssetAndApproveForAdapter(reqAssets, bob);
    //         vm.prank(bob);
    //         adapter.deposit(reqAssets, bob);
    //         prop_withdraw(bob, bob, amount, testId);

    //         _mintAssetAndApproveForAdapter(reqAssets, bob);
    //         vm.prank(bob);
    //         adapter.deposit(reqAssets, bob);

    //         increasePricePerShare(raise);

    //         vm.prank(bob);
    //         adapter.approve(alice, type(uint256).max);
    //         prop_withdraw(alice, bob, amount, testId);
    //     }
    // }

    // function test__redeem(uint8 fuzzAmount) public override {
    //     testConfigStorage = ITestConfigStorage(
    //         address(new DotDotTestConfigStorage())
    //     );

    //     uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxShares);
    //     uint8 len = uint8(testConfigStorage.getTestConfigLength());
    //     for (uint8 i; i < len; i++) {
    //         if (i > 0) overrideSetup(testConfigStorage.getTestConfig(i));

    //         uint256 reqAssets = (adapter.previewMint(amount) * 10) / 9;
    //         _mintAssetAndApproveForAdapter(reqAssets, bob);
    //         vm.prank(bob);
    //         adapter.deposit(reqAssets, bob);
    //         prop_redeem(bob, bob, amount, testId);

    //         _mintAssetAndApproveForAdapter(reqAssets, bob);
    //         vm.prank(bob);
    //         adapter.deposit(reqAssets, bob);

    //         increasePricePerShare(raise);

    //         vm.prank(bob);
    //         adapter.approve(alice, type(uint256).max);
    //         prop_redeem(alice, bob, amount, testId);
    //     }
    // }

    // /*//////////////////////////////////////////////////////////////
    //                           PAUSE
    // //////////////////////////////////////////////////////////////*/

    // function test__unpause() public override {
    //     _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

    //     vm.prank(bob);
    //     adapter.deposit(defaultAmount, bob);

    //     uint256 oldTotalAssets = adapter.totalAssets();
    //     uint256 oldTotalSupply = adapter.totalSupply();
    //     uint256 oldIouBalance = iouBalance();

    //     adapter.pause();
    //     adapter.unpause();

    //     // We simply deposit back into the external protocol
    //     // TotalSupply and Assets dont change
    //     // @dev overriden _delta_
    //     assertApproxEqAbs(
    //         oldTotalAssets,
    //         adapter.totalAssets(),
    //         50,
    //         "totalAssets"
    //     );
    //     assertApproxEqAbs(
    //         oldTotalSupply,
    //         adapter.totalSupply(),
    //         50,
    //         "totalSupply"
    //     );
    //     assertApproxEqAbs(
    //         asset.balanceOf(address(adapter)),
    //         0,
    //         50,
    //         "asset balance"
    //     );
    //     assertApproxEqRel(iouBalance(), oldIouBalance, 1, "iou balance");

    //     // Deposit and mint dont revert
    //     vm.startPrank(bob);
    //     adapter.deposit(defaultAmount, bob);
    //     adapter.mint(defaultAmount, bob);
    // }
}
