// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {VaultRouter} from "src/utils/VaultRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626} from "../mocks/MockERC4626.sol";
import {MockGauge} from "../mocks/MockGauge.sol";

contract VaultRouterTest is Test {
    VaultRouter public router;
    MockERC20 public asset;
    MockERC4626 public vault;
    MockGauge public gauge;
    address public user = address(0x1);

    function setUp() public {
        router = new VaultRouter();
        asset = new MockERC20("Test Asset", "TAST", 18);
        vault = new MockERC4626();
        vault.initialize(asset, "Test Vault", "vTAST");
        gauge = new MockGauge(address(vault));

        // Mint some assets to the user
        asset.mint(user, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                            SYNC FLOW
    //////////////////////////////////////////////////////////////*/

    function test__depositAndStake() public {
        uint256 amount = 100e18;
        uint256 minOut = 99e18; // Assuming 1% max slippage

        vm.startPrank(user);
        asset.approve(address(router), amount);
        router.depositAndStake(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();

        assertEq(gauge.balanceOf(user), amount);
        assertEq(asset.balanceOf(user), 0);
    }

    function test__unstakeAndWithdraw() public {
        // First, deposit and stake
        test__depositAndStake();

        uint256 amount = 100e18;
        uint256 minOut = 99e18; // Assuming 1% max slippage

        vm.startPrank(user);
        gauge.approve(address(router), amount);
        router.unstakeAndWithdraw(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();

        assertEq(gauge.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), 100e18);
    }

    function test__slippageProtection_depositAndStake() public {
        uint256 amount = 100e18;
        uint256 minOut = 101e18; // Set minOut higher than possible output

        vm.startPrank(user);
        asset.approve(address(router), amount);
        vm.expectRevert(VaultRouter.SlippageTooHigh.selector);
        router.depositAndStake(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();
    }

    function test__slippageProtection_unstakeAndWithdraw() public {
        // First, deposit and stake
        test__depositAndStake();

        uint256 amount = 100e18;
        uint256 minOut = 101e18; // Set minOut higher than possible output

        vm.startPrank(user);
        gauge.approve(address(router), amount);
        vm.expectRevert(VaultRouter.SlippageTooHigh.selector);
        router.unstakeAndWithdraw(
            address(vault),
            address(gauge),
            amount,
            minOut,
            user
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            ASYNC FLOW
    //////////////////////////////////////////////////////////////*/

    function test__requestWithdrawal() public {
        // First, deposit
        uint256 amount = 100e18;
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);

        vault.approve(address(router), amount);
        router.requestWithdrawal(address(vault), user, amount);
        vm.stopPrank();

        assertEq(router.requestShares(address(vault), user), amount);
    }

    function test__unstakeAndRequestWithdrawal() public {
        // First, deposit and stake
        test__depositAndStake();

        uint256 amount = 100e18;

        vm.startPrank(user);
        gauge.approve(address(router), amount);
        router.unstakeAndRequestWithdrawal(
            address(gauge),
            address(vault),
            user,
            amount
        );
        vm.stopPrank();

        assertEq(gauge.balanceOf(user), 0);
        assertEq(router.requestShares(address(vault), user), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST FULLFILLMENT
    //////////////////////////////////////////////////////////////*/

    function test__fullfillWithdrawal() public {
        // First, request withdrawal
        test__requestWithdrawal();

        uint256 amount = 100e18;

        router.fullfillWithdrawal(address(vault), user, amount);

        assertEq(router.requestShares(address(vault), user), 0);
        assertEq(asset.balanceOf(user), 100e18);
    }

    function test__fullfillWithdrawals_MultipleReceivers() public {
        // Setup: Request withdrawals for multiple users
        address user2 = address(0x2);
        address user3 = address(0x3);
        uint256 amount1 = 100e18;
        uint256 amount2 = 150e18;
        uint256 amount3 = 200e18;

        // Mint assets and approve for all users
        asset.mint(user2, 150e18);
        asset.mint(user3, 200e18);

        vm.startPrank(user);
        asset.approve(address(vault), amount1);
        vault.deposit(amount1, user);
        vault.approve(address(router), amount1);
        router.requestWithdrawal(address(vault), user, amount1);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), amount2);
        vault.deposit(amount2, user2);
        vault.approve(address(router), amount2);
        router.requestWithdrawal(address(vault), user2, amount2);
        vm.stopPrank();

        vm.startPrank(user3);
        asset.approve(address(vault), amount3);
        vault.deposit(amount3, user3);
        vault.approve(address(router), amount3);
        router.requestWithdrawal(address(vault), user3, amount3);
        vm.stopPrank();

        // Prepare arrays for fullfillWithdrawals
        address[] memory receivers = new address[](3);
        receivers[0] = user;
        receivers[1] = user2;
        receivers[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;

        // Execute fullfillWithdrawals
        router.fullfillWithdrawals(address(vault), receivers, amounts);

        // Assert results
        assertEq(router.requestShares(address(vault), user), 0);
        assertEq(router.requestShares(address(vault), user2), 0);
        assertEq(router.requestShares(address(vault), user3), 0);

        assertEq(asset.balanceOf(user), 100e18);
        assertEq(asset.balanceOf(user2), 150e18);
        assertEq(asset.balanceOf(user3), 200e18);
    }

    function test__fullfillWithdrawals_array_mismatch() public {
        address[] memory receivers = new address[](2);
        receivers[0] = user;
        receivers[1] = address(0x2);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        vm.expectRevert(VaultRouter.ArrayMismatch.selector);
        router.fullfillWithdrawals(address(vault), receivers, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                           CANCEL REQUEST
    //////////////////////////////////////////////////////////////*/

    function test__cancelRequest() public {
        // First, request withdrawal
        test__requestWithdrawal();

        uint256 amount = 100e18;

        vm.prank(user);
        router.cancelRequest(address(vault), amount);

        assertEq(router.requestShares(address(vault), user), 0);
    }

    function test__cancelRequest_insufficient_shares() public {
        test__requestWithdrawal();

        uint256 cancelAmount = 1000e18;

        vm.startPrank(user);
        vm.expectRevert(); // panic: underflow
        router.cancelRequest(address(vault), cancelAmount);
        vm.stopPrank();
    }
}
