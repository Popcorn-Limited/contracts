// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {BaseControlledAsyncRedeem, BaseERC7540} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {RequestBalance} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {AsyncVault, InitializeParams, Limits, Fees, Bounds} from "src/vaults/multisig/phase1/AsyncVault.sol";
import "forge-std/console.sol";

contract MockControlledAsyncRedeem is BaseControlledAsyncRedeem {
    constructor(
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol
    ) BaseERC7540(_owner, _asset, _name, _symbol) {}

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract BaseControlledAsyncRedeemTest is Test {
    MockControlledAsyncRedeem baseVault;
    address assetReceiver;
    MockERC20 asset;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);

    uint256 constant INITIAL_DEPOSIT = 100e18;
    uint256 constant REQUEST_ID = 0;

    event RedeemRequested(
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

    function setUp() public virtual {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");

        asset = new MockERC20("Test Token", "TEST", 18);
        baseVault = new MockControlledAsyncRedeem(
            owner,
            address(asset),
            "baseVault Token",
            "vTEST"
        );
        assetReceiver = address(baseVault);

        // Setup initial state
        asset.mint(alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(baseVault), type(uint256).max);
        baseVault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit() public virtual {
        uint256 depositAmount = 50e18;

        asset.mint(bob, depositAmount);

        vm.startPrank(bob);
        asset.approve(address(baseVault), depositAmount);
        uint256 shares = baseVault.deposit(depositAmount, bob);
        vm.stopPrank();

        assertEq(shares, depositAmount);
        assertEq(baseVault.balanceOf(bob), depositAmount);
        assertEq(
            asset.balanceOf(assetReceiver),
            INITIAL_DEPOSIT + depositAmount
        );
    }

    function testDepositToReceiver() public virtual {
        uint256 depositAmount = 50e18;
        asset.mint(bob, depositAmount);

        vm.startPrank(bob);
        asset.approve(address(baseVault), depositAmount);
        uint256 shares = baseVault.deposit(depositAmount, charlie);
        vm.stopPrank();

        assertEq(shares, depositAmount);
        assertEq(baseVault.balanceOf(charlie), depositAmount);
        assertEq(
            asset.balanceOf(assetReceiver),
            INITIAL_DEPOSIT + depositAmount
        );
    }

    // function testDepositWithClaimableAssets() public virtual {
    //     uint256 redeemAmount = 50e18;
    //     uint256 depositAmount = 30e18;

    //     // Setup and fulfill redeem request
    //     uint256 totalSupplyBefore = baseVault.totalSupply();
    //     vm.startPrank(alice);
    //     baseVault.approve(address(baseVault), redeemAmount);
    //     baseVault.requestRedeem(redeemAmount, alice, alice);
    //     vm.stopPrank();

    //     vm.startPrank(owner);
    //     baseVault.fulfillRedeem(redeemAmount, alice);
    //     vm.stopPrank();

    //     // Deposit using claimable assets
    //     vm.startPrank(alice);
    //     uint256 shares = baseVault.deposit(depositAmount, alice);
    //     vm.stopPrank();

    //     uint256 totalSupplyAfter = baseVault.totalSupply();

    //     assertEq(shares, depositAmount);
    //     assertEq(
    //         baseVault.balanceOf(alice),
    //         INITIAL_DEPOSIT - redeemAmount + depositAmount
    //     );

    //     // Check that claimable assets were reduced
    //     RequestBalance memory balance = baseVault.getRequestBalance(alice);
    //     assertEq(balance.claimableAssets, redeemAmount - depositAmount);
    //     assertEq(balance.claimableShares, redeemAmount - depositAmount);
    //     assertEq(totalSupplyBefore, totalSupplyAfter, "total supply inflated");
    // }

    // function testDepositWithPartialClaimableAssets() public virtual {
    //     uint256 redeemAmount = 50e18;
    //     uint256 depositAmount = 60e18;

    //     // Setup and fulfill redeem request
    //     uint256 totalSupplyBefore = baseVault.totalSupply();
    //     vm.startPrank(alice);
    //     baseVault.approve(address(baseVault), redeemAmount);
    //     baseVault.requestRedeem(redeemAmount, alice, alice);
    //     vm.stopPrank();

    //     vm.startPrank(owner);
    //     baseVault.fulfillRedeem(redeemAmount, alice);
    //     vm.stopPrank();

    //     // Deposit using claimable assets
    //     asset.mint(alice, 10e18);
    //     vm.startPrank(alice);
    //     asset.approve(address(baseVault), depositAmount);
    //     uint256 shares = baseVault.deposit(depositAmount, alice);
    //     vm.stopPrank();

    //     uint256 totalSupplyAfter = baseVault.totalSupply();

    //     assertEq(shares, depositAmount);
    //     assertEq(
    //         baseVault.balanceOf(alice),
    //         INITIAL_DEPOSIT - redeemAmount + depositAmount
    //     );

    //     // Check that claimable assets were reduced
    //     RequestBalance memory balance = baseVault.getRequestBalance(alice);
    //     assertEq(balance.claimableAssets, 0);
    //     assertEq(balance.claimableShares, 0);
    //     assertEq(
    //         totalSupplyAfter,
    //         totalSupplyBefore + 10e18,
    //         "total supply inflated"
    //     );
    // }

    function testFailDepositZero() public virtual {
        vm.prank(bob);
        baseVault.deposit(0, bob);
    }

    function testFailDepositWhenPaused() public virtual {
        asset.mint(bob, 100e18);

        vm.prank(owner);
        baseVault.pause();

        vm.prank(bob);
        baseVault.deposit(100e18, bob);
    }

    function testMint() public virtual {
        uint256 mintAmount = 50e18;

        asset.mint(bob, mintAmount);

        vm.startPrank(bob);
        asset.approve(address(baseVault), mintAmount);
        uint256 assets = baseVault.mint(mintAmount, bob);
        vm.stopPrank();

        assertEq(assets, mintAmount);
        assertEq(baseVault.balanceOf(bob), mintAmount);
        assertEq(asset.balanceOf(assetReceiver), INITIAL_DEPOSIT + mintAmount);
    }

    function testMintToReceiver() public virtual {
        uint256 mintAmount = 50e18;
        asset.mint(bob, mintAmount);

        vm.startPrank(bob);
        asset.approve(address(baseVault), mintAmount);
        uint256 assets = baseVault.mint(mintAmount, charlie);
        vm.stopPrank();

        assertEq(assets, mintAmount);
        assertEq(baseVault.balanceOf(charlie), mintAmount);
        assertEq(asset.balanceOf(assetReceiver), INITIAL_DEPOSIT + mintAmount);
    }

    // function testMintWithClaimableAssets() public virtual {
    //     uint256 redeemAmount = 50e18;
    //     uint256 mintAmount = 30e18;

    //     uint256 totalSupplyBefore = baseVault.totalSupply();

    //     // Setup and fulfill redeem request
    //     vm.startPrank(alice);
    //     baseVault.approve(address(baseVault), redeemAmount);
    //     baseVault.requestRedeem(redeemAmount, alice, alice);
    //     vm.stopPrank();

    //     vm.startPrank(owner);
    //     baseVault.fulfillRedeem(redeemAmount, alice);
    //     vm.stopPrank();

    //     uint256 totalSupplyAfter = baseVault.totalSupply();

    //     // Deposit using claimable assets
    //     vm.startPrank(alice);
    //     uint256 shares = baseVault.mint(mintAmount, alice);
    //     vm.stopPrank();

    //     assertEq(shares, mintAmount);
    //     assertEq(
    //         baseVault.balanceOf(alice),
    //         INITIAL_DEPOSIT - redeemAmount + mintAmount
    //     );

    //     // Check that claimable assets were reduced
    //     RequestBalance memory balance = baseVault.getRequestBalance(alice);
    //     assertEq(balance.claimableAssets, redeemAmount - mintAmount);
    //     assertEq(balance.claimableShares, redeemAmount - mintAmount);
    //     assertEq(totalSupplyBefore, totalSupplyAfter, "total supply inflated");
    // }

    function testFailMintZero() public virtual {
        vm.prank(bob);
        baseVault.mint(0, bob);
    }

    function testFailMintWhenPaused() public virtual {
        asset.mint(bob, 100e18);

        vm.prank(owner);
        baseVault.pause();

        vm.prank(bob);
        baseVault.mint(100e18, bob);
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAW / REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdraw() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.prank(owner);
        uint256 assets = baseVault.fulfillRedeem(redeemAmount, alice);

        // Withdraw
        vm.prank(alice);
        uint256 shares = baseVault.withdraw(assets, alice, alice);

        assertEq(shares, redeemAmount);
        assertEq(asset.balanceOf(alice), assets);
    }

    function testWithdrawWithOperator() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup operator
        vm.prank(alice);
        baseVault.setOperator(bob, true);

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(baseVault), redeemAmount);
        uint256 assets = baseVault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        // Withdraw using operator
        vm.prank(bob);
        baseVault.withdraw(assets, bob, alice);

        assertEq(asset.balanceOf(bob), assets);
    }

    function testFailWithdrawZero() public virtual {
        vm.prank(alice);
        baseVault.withdraw(0, alice, alice);
    }

    function testRedeem() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.prank(owner);
        baseVault.fulfillRedeem(redeemAmount, alice);

        // Redeem
        vm.prank(alice);
        uint256 assets = baseVault.redeem(redeemAmount, alice, alice);

        assertEq(asset.balanceOf(alice), assets);
        assertEq(assets, redeemAmount);
    }

    function testRedeem_issueM01() public virtual {
        uint256 mintAmount = 100e18;

        asset.mint(bob, mintAmount);

        vm.startPrank(bob);
        asset.approve(address(baseVault), mintAmount);
        uint256 assets = baseVault.mint(mintAmount, bob);
        vm.stopPrank();

        uint256 redeemAmount = 100e18;

        // Setup and redeem request with full balance
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // fulfill but leave the assets idle
        vm.prank(owner);
        baseVault.fulfillRedeem(redeemAmount, alice);

        // mint as "yield"
        asset.mint(address(baseVault), 10e18);

        // Setup and fulfill redeem request
        vm.startPrank(bob);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, bob, bob);
        vm.stopPrank();

        baseVault.fulfillRedeem(redeemAmount, bob);

        // Redeem
        vm.prank(bob);
        uint256 bobAssets = baseVault.redeem(redeemAmount, bob, bob);
        assertEq(bobAssets, 110e18, "BOB"); // fails

        // alice redeem - should have 0 yield
        // this is correct, issue is that bob receives less and
        // the remaining yield stays in the contract
        vm.prank(alice);
        uint256 aliceAssets = baseVault.redeem(redeemAmount, alice, alice);
        assertEq(aliceAssets, 100e18, "ALICE");
    }

    function testRedeemWithOperator() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup operator
        vm.prank(alice);
        baseVault.setOperator(bob, true);

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(baseVault), redeemAmount);
        baseVault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        // Redeem using operator
        vm.prank(bob);
        uint256 assets = baseVault.redeem(redeemAmount, bob, alice);

        assertEq(asset.balanceOf(bob), assets);
        assertEq(assets, redeemAmount);
    }

    function testFailRedeemZero() public virtual {
        vm.prank(alice);
        baseVault.redeem(0, alice, alice);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPendingRedeemRequest() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        assertEq(
            baseVault.pendingRedeemRequest(REQUEST_ID, alice),
            redeemAmount
        );
    }

    function testClaimableRedeemRequest() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(baseVault), redeemAmount);
        baseVault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        assertEq(
            baseVault.claimableRedeemRequest(REQUEST_ID, alice),
            redeemAmount
        );
    }

    function testMaxWithdraw() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(baseVault), redeemAmount);
        uint256 assets = baseVault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        assertEq(baseVault.maxWithdraw(alice), assets);
    }

    function testMaxRedeem() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup and fulfill redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(baseVault), redeemAmount);
        baseVault.fulfillRedeem(redeemAmount, alice);
        vm.stopPrank();

        assertEq(baseVault.maxRedeem(alice), redeemAmount);
    }

    function testPreviewWithdrawReverts() public virtual {
        vm.expectRevert("ERC7540Vault/async-flow");
        baseVault.previewWithdraw(INITIAL_DEPOSIT);
    }

    function testPreviewRedeemReverts() public virtual {
        vm.expectRevert("ERC7540Vault/async-flow");
        baseVault.previewRedeem(INITIAL_DEPOSIT);
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRedeem() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);

        baseVault.requestRedeem(redeemAmount, alice, alice);

        RequestBalance memory balance = baseVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, redeemAmount);
        assertEq(balance.requestTime, block.timestamp);
        assertEq(balance.claimableShares, 0);
        assertEq(balance.claimableAssets, 0);
        vm.stopPrank();
    }

    function testRequestRedeemWithOperator() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.prank(alice);
        baseVault.approve(address(baseVault), redeemAmount);

        vm.prank(alice);
        baseVault.setOperator(bob, true);

        vm.startPrank(bob);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();
    }

    function testFailRequestRedeemUnauthorized() public virtual {
        vm.prank(bob);
        baseVault.requestRedeem(100e18, alice, alice);
    }

    function testFailRequestRedeemZeroShares() public virtual {
        vm.prank(alice);
        baseVault.requestRedeem(0, alice, alice);
    }

    /*//////////////////////////////////////////////////////////////
                    CANCEL REDEEM REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelRedeemRequest() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);

        baseVault.fulfillRedeem(redeemAmount / 2, alice);

        vm.expectEmit(true, true, true, true);
        emit RedeemRequestCanceled(alice, alice, redeemAmount / 2);
        baseVault.cancelRedeemRequest(alice);

        RequestBalance memory balance = baseVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0);
        assertEq(balance.requestTime, 0);
        assertEq(balance.claimableShares, redeemAmount / 2);
        assertEq(balance.claimableAssets, redeemAmount / 2);
        assertEq(baseVault.balanceOf(alice), redeemAmount / 2);
    }

    function testCancelRedeemRequestWithReceiver() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);

        vm.expectEmit(true, true, true, true);
        emit RedeemRequestCanceled(alice, bob, redeemAmount);
        baseVault.cancelRedeemRequest(alice, bob);
    }

    function testFailCancelRedeemRequestUnauthorized() public virtual {
        vm.prank(bob);
        baseVault.cancelRedeemRequest(alice);
    }

    function testFailCancelRedeemRequestNoPendingRequest() public virtual {
        vm.prank(alice);
        baseVault.cancelRedeemRequest(alice);
    }

    function testFailCancelRedeemRequestZeroShares() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);

        baseVault.fulfillRedeem(redeemAmount / 2, alice);

        vm.expectRevert("ERC7540Vault/no-pending-request");
        baseVault.cancelRedeemRequest(alice, bob);
    }

    /*//////////////////////////////////////////////////////////////
                    FULFILL REDEEM REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testFulfillRedeem() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Setup redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Fulfill request
        vm.startPrank(owner);
        asset.mint(owner, redeemAmount);
        asset.approve(address(baseVault), redeemAmount);
        uint256 assets = baseVault.fulfillRedeem(redeemAmount, alice);

        RequestBalance memory balance = baseVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0, "1");
        assertEq(balance.claimableShares, redeemAmount, "2");
        assertEq(balance.claimableAssets, assets, "3");
        vm.stopPrank();

        assertEq(asset.balanceOf(assetReceiver), redeemAmount, "4");
        assertEq(baseVault.totalAssets(), redeemAmount, "5");
    }

    function testPartialFulfillRedeem() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;
        uint256 partialAmount = 60e18;

        // Setup redeem request
        vm.startPrank(alice);
        baseVault.approve(address(baseVault), redeemAmount);
        baseVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Partially fulfill request
        vm.startPrank(owner);
        asset.mint(owner, partialAmount);
        asset.approve(address(baseVault), partialAmount);
        uint256 assets = baseVault.fulfillRedeem(partialAmount, alice);

        RequestBalance memory balance = baseVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, redeemAmount - partialAmount);
        assertEq(balance.claimableShares, partialAmount);
        assertEq(balance.claimableAssets, assets);
        vm.stopPrank();
    }

    function testFulfillRedeemWithEmptyRequestBalance() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        vm.expectRevert();
        baseVault.fulfillRedeem(redeemAmount, alice);

        // Verify request balance remains empty
        RequestBalance memory balance = baseVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0);
        assertEq(balance.claimableShares, 0);
        assertEq(balance.claimableAssets, 0);
    }

    function testFailFulfillRedeemZeroShares() public virtual {
        vm.startPrank(owner);
        baseVault.fulfillRedeem(0, alice);
    }
}
