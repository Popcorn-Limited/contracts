// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {VaultRouter} from "src/utils/VaultRouter.sol";
import {MockERC20, ERC20} from "test/mocks/MockERC20.sol";
import {MockERC7540, InitializeParams, Limits, Fees} from "test/mocks/MockERC7540.sol";
import {MockGauge} from "test/mocks/MockGauge.sol";

contract VaultRouterTest is Test {
    VaultRouter public router;
    MockERC20 public asset;
    MockERC7540 public vault;
    MockGauge public gauge;
    address public user = address(0x1);
    address public user2 = address(0x2);

    function setUp() public {
        router = new VaultRouter();
        asset = new MockERC20("Test Asset", "TAST", 18);
        vault = new MockERC7540(
            InitializeParams({
                asset: address(asset),
                name: "Vault Token",
                symbol: "vTEST",
                owner: address(this),
                limits: Limits({depositLimit: type(uint256).max, minAmount: 0}),
                fees: Fees({
                    performanceFee: 0,
                    managementFee: 0,
                    withdrawalIncentive: 0,
                    feesUpdatedAt: uint64(block.timestamp),
                    highWaterMark: 1e18,
                    feeRecipient: address(this)
                })
            })
        );
        gauge = new MockGauge(address(vault));

        // Mint some assets to the user
        asset.mint(user, 100e18);

        vm.startPrank(user);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100e18, user);
        vault.approve(address(gauge), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        UNSTAKE AND REQUEST
    //////////////////////////////////////////////////////////////*/

    function test__unstakeAndRequestWithdrawal() public {
        // Test Preparation
        vm.startPrank(user);
        gauge.deposit(100e18, user);
        gauge.approve(address(router), type(uint256).max);

        // Main call
        router.unstakeAndRequestWithdrawal(
            address(gauge),
            address(vault),
            user,
            100e18
        );

        assertEq(gauge.balanceOf(user), 0, "Gauge balance should decrease");
        assertEq(
            vault.pendingRedeemRequest(0, user),
            100e18,
            "Should have outstanding request"
        );

        vm.stopPrank();
    }

    function test__unstakeAndRequestWithdrawal_for_receiver() public {
        // Test Preparation
        vm.startPrank(user);
        gauge.deposit(100e18, user);
        gauge.approve(address(router), type(uint256).max);

        // Main call
        router.unstakeAndRequestWithdrawal(
            address(gauge),
            address(vault),
            user2,
            100e18
        );

        assertEq(gauge.balanceOf(user), 0, "Gauge balance should decrease");
        assertEq(
            vault.pendingRedeemRequest(0, user),
            0,
            "Should have no outstanding request"
        );
        assertEq(
            vault.pendingRedeemRequest(0, user2),
            100e18,
            "Should have outstanding request"
        );

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST AND FULFILL
    //////////////////////////////////////////////////////////////*/

    function test__requestFulfillWithdraw() public {
        // Test Preparation
        vm.startPrank(user);
        vault.approve(address(router), type(uint256).max);
        vault.setOperator(address(router), true);

        // Main call
        router.requestFulfillWithdraw(
            address(vault),
            user,
            100e18
        );

        // Verify final balances
        assertEq(vault.balanceOf(user), 0, "Vault balance should not change");
        assertEq(
            asset.balanceOf(user),
            100e18,
            "Asset balance not increased"
        );

        vm.stopPrank();
    }

    function test__requestFulfillWithdraw_for_receiver() public {
        // Test Preparation
        vm.prank(user2);
        vault.setOperator(address(router), true);

        vm.startPrank(user);
        vault.approve(address(router), type(uint256).max);
        vault.setOperator(address(router), true);

        // Main call
        router.requestFulfillWithdraw(
            address(vault),
            user2,
            100e18
        );

        // Verify final balances
        assertEq(vault.balanceOf(user), 0, "Vault balance should not change");
        assertEq(
            asset.balanceOf(user2),
            100e18,
            "Asset balance not increased"
        );

        vm.stopPrank();
    }

    function testFail__requestFulfillWithdraw_not_operator() public {
        // Test Preparation
        vm.startPrank(user);
        vault.approve(address(router), type(uint256).max);

        // Main call
        router.requestFulfillWithdraw(
            address(vault),
            user,
            100e18
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    UNSTAKE, REQUEST AND FULFILL
    //////////////////////////////////////////////////////////////*/

    function test__unstakeRequestFulfillWithdraw() public {
        // Test Preparation
        vm.startPrank(user);
        gauge.deposit(100e18, user);
        gauge.approve(address(router), type(uint256).max);
        vault.setOperator(address(router), true);

        // Main call
        router.unstakeRequestFulfillWithdraw(
            address(gauge),
            address(vault),
            user,
            100e18
        );

        // Verify final balances
        assertEq(gauge.balanceOf(user), 0, "Gauge balance not decreased");
        assertEq(vault.balanceOf(user), 0, "Vault balance should not change");
        assertEq(
            asset.balanceOf(user),
            100e18,
            "Asset balance not increased"
        );

        vm.stopPrank();
    }

    function test__unstakeRequestFulfillWithdraw_for_receiver() public {
        // Test Preparation
        vm.prank(user2);
        vault.setOperator(address(router), true);

        vm.startPrank(user);
        gauge.deposit(100e18, user);
        gauge.approve(address(router), type(uint256).max);
        vault.setOperator(address(router), true);

        // Main call
        router.unstakeRequestFulfillWithdraw(
            address(gauge),
            address(vault),
            user2,
            100e18
        );

        // Verify final balances
        assertEq(gauge.balanceOf(user), 0, "Gauge balance not decreased");
        assertEq(vault.balanceOf(user), 0, "Vault balance should not change");
        assertEq(
            asset.balanceOf(user2),
            100e18,
            "Asset balance not increased"
        );

        vm.stopPrank();
    }

    function testFail__unstakeRequestFulfillWithdraw_not_operator() public {
        // Test Preparation
        vm.startPrank(user);
        gauge.deposit(100e18, user);
        gauge.approve(address(router), type(uint256).max);

        // Main call
        router.unstakeRequestFulfillWithdraw(
            address(gauge),
            address(vault),
            user,
            100e18
        );
        vm.stopPrank();
    }
}
