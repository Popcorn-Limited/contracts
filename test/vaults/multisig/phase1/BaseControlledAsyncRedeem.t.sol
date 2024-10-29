// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {BaseControlledAsyncRedeem, BaseERC7540} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {RequestBalance} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {AsyncVault, InitializeParams, Limits, Fees, Bounds} from "src/vaults/multisig/phase1/AsyncVault.sol";

contract MockControlledAsyncRedeem is BaseControlledAsyncRedeem {
    constructor(
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol
    ) BaseERC7540(_owner, _asset, _name, _symbol) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract BaseControlledAsyncRedeemTest is Test {
    MockControlledAsyncRedeem vault;
    MockERC20 asset;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);

    uint256 constant INITIAL_DEPOSIT = 100e18;
    uint256 constant REQUEST_ID = 0;

    event RedeemRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address operator,
        uint256 shares
    );

    event RedeemRequestCanceled(
        address indexed controller,
        address indexed receiver,
        uint256 shares
    );

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");

        asset = new MockERC20("Test Token", "TEST", 18);
        vault = new MockControlledAsyncRedeem(
            owner,
            address(asset),
            "Vault Token",
            "vTEST"
        );

        // Setup initial state
        asset.mint(alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRedeem() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);

        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(alice, alice, REQUEST_ID, alice, redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);

        RequestBalance memory balance = vault.getRequestBalance(alice);
        assertEq(balance.pendingShares, redeemAmount);
        assertEq(balance.requestTime, block.timestamp);
        assertEq(balance.claimableShares, 0);
        assertEq(balance.claimableAssets, 0);
        vm.stopPrank();
    }

    function testRequestRedeemWithOperator() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.prank(alice);
        vault.approve(address(vault), redeemAmount);

        vm.prank(alice);
        vault.setOperator(bob, true);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit RedeemRequest(alice, alice, REQUEST_ID, bob, redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();
    }

    function testFailRequestRedeemUnauthorized() public {
        vm.prank(bob);
        vault.requestRedeem(100e18, alice, alice);
    }

    function testFailRequestRedeemInsufficientBalance() public {
        vm.prank(alice);
        vault.requestRedeem(INITIAL_DEPOSIT + 1, alice, alice);
    }

    /*//////////////////////////////////////////////////////////////
                    CANCEL REDEEM REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRedeemRequest() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);

        vm.expectEmit(true, true, true, true);
        emit RedeemRequestCanceled(alice, alice, redeemAmount);
        vault.cancelRedeemRequest(alice);

        RequestBalance memory balance = vault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0);
        assertEq(balance.requestTime, 0);
        vm.stopPrank();
    }

    function testCancelRedeemRequestWithReceiver() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);

        vm.expectEmit(true, true, true, true);
        emit RedeemRequestCanceled(alice, bob, redeemAmount);
        vault.cancelRedeemRequest(alice, bob);
        vm.stopPrank();
    }

    function testFailCancelRedeemRequestUnauthorized() public {
        vm.prank(bob);
        vault.cancelRedeemRequest(alice);
    }

    /*//////////////////////////////////////////////////////////////
                    FULFILL REDEEM REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testFulfillRedeem() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Fulfill request
        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(vault), redeemAmount);
        uint256 assets = vault.fulfillRedeem(redeemAmount, alice);

        RequestBalance memory balance = vault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0);
        assertEq(balance.claimableShares, redeemAmount);
        assertEq(balance.claimableAssets, assets);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), redeemAmount);
        assertEq(vault.totalAssets(), redeemAmount);
    }

    function testPartialFulfillRedeem() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;
        uint256 partialAmount = 60e18;

        // Setup redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Partially fulfill request
        vm.startPrank(owner);
        asset.mint(owner, partialAmount);
        asset.approve(address(vault), partialAmount);
        uint256 assets = vault.fulfillRedeem(partialAmount, alice);

        RequestBalance memory balance = vault.getRequestBalance(alice);
        assertEq(balance.pendingShares, redeemAmount - partialAmount);
        assertEq(balance.claimableShares, partialAmount);
        assertEq(balance.claimableAssets, assets);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdraw() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.prank(owner);
        uint256 assets = vault.fulfillRedeem(redeemAmount, alice);

        // Withdraw
        vm.prank(alice);
        uint256 shares = vault.withdraw(assets, alice, alice);

        assertEq(shares, redeemAmount);
        assertEq(asset.balanceOf(alice), assets);
    }

    function testWithdrawWithOperator() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup operator
        vm.prank(alice);
        vault.setOperator(bob, true);

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(vault), redeemAmount);
        uint256 assets = vault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        // Withdraw using operator
        vm.prank(bob);
        vault.withdraw(assets, bob, alice);

        assertEq(asset.balanceOf(bob), assets);
    }

    function testRedeem() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.prank(owner);
        vault.fulfillRedeem(redeemAmount, alice);

        // Redeem
        vm.prank(alice);
        uint256 assets = vault.redeem(redeemAmount, alice, alice);

        assertEq(asset.balanceOf(alice), assets);
        assertEq(assets, redeemAmount);
    }

    function testRedeemWithOperator() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup operator
        vm.prank(alice);
        vault.setOperator(bob, true);

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(vault), redeemAmount);
        vault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        // Redeem using operator
        vm.prank(bob);
        uint256 assets = vault.redeem(redeemAmount, bob, alice);

        assertEq(asset.balanceOf(bob), assets);
        assertEq(assets, redeemAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPendingRedeemRequest() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        assertEq(vault.pendingRedeemRequest(REQUEST_ID, alice), redeemAmount);
    }

    function testClaimableRedeemRequest() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(vault), redeemAmount);
        vault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        assertEq(vault.claimableRedeemRequest(REQUEST_ID, alice), redeemAmount);
    }

    function testMaxWithdraw() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(vault), redeemAmount);
        uint256 assets = vault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        assertEq(vault.maxWithdraw(alice), assets);
    }

    function testMaxRedeem() public {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(vault), redeemAmount);
        vault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        assertEq(vault.maxRedeem(alice), redeemAmount);
    }

    function testPreviewWithdrawReverts() public {
        vm.expectRevert("ERC7540Vault/async-flow");
        vault.previewWithdraw(INITIAL_DEPOSIT);
    }

    function testPreviewRedeemReverts() public {
        vm.expectRevert("ERC7540Vault/async-flow");
        vault.previewRedeem(INITIAL_DEPOSIT);
    }
}
