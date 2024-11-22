// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {BaseControlledAsyncRedeemTest, MockControlledAsyncRedeem} from "./BaseControlledAsyncRedeem.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {AsyncVault, InitializeParams, Limits, Fees, Bounds} from "src/vaults/multisig/phase1/AsyncVault.sol";
import {RequestBalance} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract MockAsyncVault is AsyncVault {
    constructor(InitializeParams memory params) AsyncVault(params) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract AsyncVaultTest is BaseControlledAsyncRedeemTest {
    using FixedPointMathLib for uint256;

    MockAsyncVault asyncVault;

    address feeRecipient = address(0x5);

    uint256 constant ONE = 1e18;

    event FeesUpdated(Fees prev, Fees next);
    event LimitsUpdated(Limits prev, Limits next);

    function setUp() public virtual override {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(feeRecipient, "feeRecipient");

        asset = new MockERC20("Test Token", "TEST", 18);

        InitializeParams memory params = InitializeParams({
            asset: address(asset),
            name: "Vault Token",
            symbol: "vTEST",
            owner: owner,
            limits: Limits({depositLimit: type(uint256).max, minAmount: 0}),
            fees: Fees({
                performanceFee: 0,
                managementFee: 0,
                withdrawalIncentive: 0,
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        asyncVault = new MockAsyncVault(params);

        // For inherited tests
        baseVault = MockControlledAsyncRedeem(address(asyncVault));
        assetReceiver = address(asyncVault);

        // Setup initial state
        asset.mint(alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(baseVault), type(uint256).max);
        baseVault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testPreviewDeposit() public virtual {
        uint256 depositAmount = 100e18;
        uint256 expectedShares = asyncVault.convertToShares(depositAmount);
        assertEq(asyncVault.previewDeposit(depositAmount), expectedShares);
    }

    function testPreviewDepositBelowMin() public virtual {
        vm.prank(owner);
        asyncVault.setLimits(
            Limits({depositLimit: type(uint256).max, minAmount: 1e18})
        );

        uint256 depositAmount = 0.5e18;
        assertEq(asyncVault.previewDeposit(depositAmount), 0);
    }

    function testPreviewMint() public virtual {
        uint256 mintAmount = 100e18;
        uint256 expectedAssets = asyncVault.convertToAssets(mintAmount);
        assertEq(asyncVault.previewMint(mintAmount), expectedAssets);
    }

    function testPreviewMintBelowMin() public virtual {
        vm.prank(owner);
        asyncVault.setLimits(
            Limits({depositLimit: type(uint256).max, minAmount: 1e18})
        );

        uint256 mintAmount = 0.5e18;
        assertEq(asyncVault.previewMint(mintAmount), 0);
    }

    function testConvertToLowBoundAssets() public virtual {
        testDeposit();

        // Set bounds
        Bounds memory bounds = Bounds({
            upper: 0.1e18, // 110%
            lower: 0.9e18 // 90%
        });
        vm.prank(owner);
        asyncVault.setBounds(bounds);

        uint256 shares = 100e18;
        uint256 expectedAssets = asyncVault.totalAssets().mulDivDown(
            1e18 - bounds.lower,
            1e18
        );
        uint256 expectedShares = shares.mulDivDown(
            expectedAssets,
            asyncVault.totalSupply()
        );

        assertEq(asyncVault.convertToLowBoundAssets(shares), expectedShares);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMaxDeposit() public virtual {
        vm.prank(owner);
        asyncVault.setLimits(Limits({depositLimit: 10000e18, minAmount: 0}));

        uint256 currentAssets = asyncVault.totalAssets();
        assertEq(asyncVault.maxDeposit(alice), 10000e18 - currentAssets);
    }

    function testMaxDepositWhenPaused() public virtual {
        vm.prank(owner);
        asyncVault.pause();

        assertEq(asyncVault.maxDeposit(alice), 0);
    }

    function testMaxMint() public virtual {
        vm.prank(owner);
        asyncVault.setLimits(Limits({depositLimit: 10000e18, minAmount: 0}));

        uint256 currentAssets = asyncVault.totalAssets();
        uint256 expectedShares = asyncVault.convertToShares(
            10000e18 - currentAssets
        );
        assertEq(asyncVault.maxMint(alice), expectedShares);
    }

    function testMaxMintWhenPaused() public virtual {
        vm.prank(owner);
        asyncVault.pause();
        assertEq(asyncVault.maxMint(alice), 0);
    }

    function testMaxMintMaxUint() public virtual {
        vm.prank(owner);
        asyncVault.setLimits(
            Limits({depositLimit: type(uint256).max, minAmount: 0})
        );

        uint256 expectedShares = type(uint256).max - asyncVault.totalSupply();
        assertEq(asyncVault.maxMint(alice), expectedShares);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRedeemBelowMin() public virtual {
        vm.prank(owner);
        asyncVault.setLimits(
            Limits({depositLimit: type(uint256).max, minAmount: 1e18})
        );
        testMint();
        uint256 redeemAmount = 0.5e18;

        vm.startPrank(alice);
        asyncVault.approve(address(asyncVault), redeemAmount);

        vm.expectRevert("ERC7540Vault/min-amount");
        asyncVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        FULFILL REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testFulfillMultipleRedeems() public virtual {
        uint256 redeemAmount = 100e18;
        asset.mint(alice, redeemAmount * 2);
        asset.mint(owner, redeemAmount * 2);

        vm.startPrank(alice);
        asset.approve(address(asyncVault), redeemAmount * 2);
        asyncVault.deposit(redeemAmount * 2, alice);
        vm.stopPrank();

        // Setup redeem requests
        vm.startPrank(alice);
        asyncVault.approve(address(asyncVault), redeemAmount * 2);
        uint256 request1 = asyncVault.requestRedeem(redeemAmount, alice, alice);
        uint256 request2 = asyncVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        uint256[] memory shares = new uint256[](2);
        shares[0] = redeemAmount;
        shares[1] = redeemAmount;

        address[] memory controllers = new address[](2);
        controllers[0] = alice;
        controllers[1] = alice;

        vm.startPrank(owner);
        asset.approve(address(asyncVault), redeemAmount * 2);
        uint256 totalAssets = asyncVault.fulfillMultipleRedeems(
            shares,
            controllers
        );
        assertEq(totalAssets, redeemAmount * 2);
        vm.stopPrank();

        assertEq(asset.balanceOf(assetReceiver), redeemAmount * 3);
        assertEq(asyncVault.totalAssets(), redeemAmount * 3);
    }

    function testFulfillMultipleRedeemsWithFees() public virtual {
        uint256 redeemAmount = 100e18;
        asset.mint(alice, redeemAmount);
        asset.mint(bob, redeemAmount);

        // alice deposits
        vm.startPrank(alice);
        asset.approve(address(asyncVault), redeemAmount);
        asyncVault.deposit(redeemAmount, alice);
        vm.stopPrank();

        // bob deposits
        vm.startPrank(bob);
        asset.approve(address(asyncVault), redeemAmount);
        asyncVault.deposit(redeemAmount, bob);
        vm.stopPrank();

        // Set 1% withdrawal fee
        Fees memory newFees = Fees({
            performanceFee: 0,
            managementFee: 0,
            withdrawalIncentive: 0.01e18, // 1%
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });
        vm.prank(owner);
        asyncVault.setFees(newFees);

        // Setup redeem requests
        vm.startPrank(alice);
        asyncVault.approve(address(asyncVault), redeemAmount);
        uint256 request1 = asyncVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // bob
        vm.startPrank(bob);
        asyncVault.approve(address(asyncVault), redeemAmount);
        uint256 request2 = asyncVault.requestRedeem(redeemAmount, bob, bob);
        vm.stopPrank();

        // fulfill both requests at once
        uint256[] memory shares = new uint256[](2);
        shares[0] = redeemAmount;
        shares[1] = redeemAmount;

        address[] memory controllers = new address[](2);
        controllers[0] = alice;
        controllers[1] = bob;

        vm.startPrank(owner);
        uint256 totalAssets = asyncVault.fulfillMultipleRedeems(
            shares,
            controllers
        );

        assertEq(totalAssets, redeemAmount * 2, "return ta");
        vm.stopPrank();

        // alice withdraw
        vm.prank(alice);
        asyncVault.redeem(redeemAmount, alice, alice);

        // bob withdraw
        vm.prank(bob);
        asyncVault.redeem(redeemAmount, bob, bob);

        uint256 withdrawFee = redeemAmount / 100; // 1% fee

        assertEq(asset.balanceOf(alice), redeemAmount - withdrawFee, "alice");
        assertEq(asset.balanceOf(bob), redeemAmount - withdrawFee, "bob");
        assertEq(asset.balanceOf(feeRecipient), withdrawFee * 2, "recipient");

        assertEq(asyncVault.totalAssets(), INITIAL_DEPOSIT);
    }

    function testFulfillRedeemWithWithdrawalFee() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;

        // Set 1% withdrawal fee
        Fees memory newFees = Fees({
            performanceFee: 0,
            managementFee: 0,
            withdrawalIncentive: 0.01e18, // 1%
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });
        vm.prank(owner);
        asyncVault.setFees(newFees);

        // Setup redeem request
        vm.startPrank(alice);
        asyncVault.approve(address(asyncVault), redeemAmount);
        asyncVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Fulfill request
        vm.startPrank(owner);
        uint256 assets = asyncVault.fulfillRedeem(redeemAmount, alice);

        RequestBalance memory balance = asyncVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0);
        assertEq(balance.claimableShares, redeemAmount);
        assertEq(
            balance.claimableAssets,
            (redeemAmount * (1e18 - 0.01e18)) / 1e18
        );
        vm.stopPrank();

        // Check that assets received is 99% of redeemed amount (1% fee)
        assertEq(assets, redeemAmount);
        assertEq(
            asset.balanceOf(assetReceiver),
            (redeemAmount * (1e18 - 0.01e18)) / 1e18
        );
        assertEq(
            asyncVault.totalAssets(),
            (redeemAmount * (1e18 - 0.01e18)) / 1e18
        );
        assertEq(asset.balanceOf(feeRecipient), 1e18);
    }

    function testFulfillRedeemWithLowerBound() public virtual {
        uint256 redeemAmount = INITIAL_DEPOSIT;
        uint256 expectedAssets = (redeemAmount * (1e18 - 0.01e18)) / 1e18;

        // Set 1% lower bound
        vm.prank(owner);
        asyncVault.setBounds(
            Bounds({
                upper: 0,
                lower: 0.01e18 // 1%
            })
        );

        // Setup redeem request
        vm.startPrank(alice);
        asyncVault.approve(address(asyncVault), redeemAmount);
        asyncVault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Fulfill request
        uint256 assets = asyncVault.fulfillRedeem(redeemAmount, alice);

        RequestBalance memory balance = asyncVault.getRequestBalance(alice);
        assertEq(balance.pendingShares, 0);
        assertEq(balance.claimableShares, redeemAmount);
        assertEq(balance.claimableAssets, expectedAssets);
        vm.stopPrank();

        // Check that assets received is 99% of redeemed amount (1% lower bound)
        assertEq(assets, expectedAssets);
        assertEq(asyncVault.totalAssets(), INITIAL_DEPOSIT);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetFees() public virtual {
        Fees memory newFees = Fees({
            performanceFee: 0.15e18, // 15%
            managementFee: 0.02e18, // 2%
            withdrawalIncentive: 0.02e18, // 2%
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(newFees);

        Fees memory currentFees = asyncVault.getFees();
        assertEq(currentFees.performanceFee, newFees.performanceFee);
        assertEq(currentFees.managementFee, newFees.managementFee);
        assertEq(currentFees.withdrawalIncentive, newFees.withdrawalIncentive);
    }

    function testSetFeesRevertsTooHigh() public virtual {
        Fees memory newFees = Fees({
            performanceFee: 0.21e18, // 21% - too high
            managementFee: 0,
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        vm.expectRevert(AsyncVault.Misconfigured.selector);
        asyncVault.setFees(newFees);

        newFees.performanceFee = 0.0; // reset
        newFees.managementFee = 0.06e18; // 6% - too high

        vm.prank(owner);
        vm.expectRevert(AsyncVault.Misconfigured.selector);
        asyncVault.setFees(newFees);

        newFees.managementFee = 0; // reset
        newFees.withdrawalIncentive = 0.06e18; // 6% - too high

        vm.prank(owner);
        vm.expectRevert(AsyncVault.Misconfigured.selector);
        asyncVault.setFees(newFees);
    }

    function testAccruedFees() public virtual {
        // Set management fee to 5%
        Fees memory newFees = Fees({
            performanceFee: 0.15e18, // 15%
            managementFee: 0.05e18, // 5%
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(newFees);

        // Test management fee over one year
        vm.warp(block.timestamp + 365.25 days);
        uint256 managementFees = asyncVault.accruedFees();
        assertEq(managementFees, 5e18); // Should be 5% of 100e18 after 1 year

        // Double total assets to test performance fee
        asset.mint(address(asyncVault), 100e18);
        uint256 totalFees = asyncVault.accruedFees();
        // Should be management fee (5e18) plus performance fee (15% of 100e18 profit = 15e18)
        assertEq(totalFees, 25e18);
    }

    function testTakeFees() public virtual {
        testSetFees();

        // Simulate some yield
        asset.mint(address(asyncVault), 100e18);

        vm.warp(block.timestamp + 365.25 days);

        vm.prank(owner);
        asyncVault.takeFees();

        assertGt(asyncVault.balanceOf(feeRecipient), 0);
    }

    function testTakeFeesOnDeposit() public virtual {
        // Set management fee to 5%
        Fees memory newFees = Fees({
            performanceFee: 0,
            managementFee: 0.05e18,
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(newFees);

        // Warp forward so fees can accrue
        vm.warp(block.timestamp + 365.25 days);

        // Make a deposit which should trigger fee taking
        vm.startPrank(alice);
        asset.mint(alice, 100e18);
        asset.approve(address(asyncVault), 100e18);
        asyncVault.deposit(100e18, alice);
        vm.stopPrank();

        // Check that fees were taken and sent to fee recipient
        assertGt(asyncVault.balanceOf(feeRecipient), 0);
    }

    function testTakeFeesOnWithdraw() public virtual {
        // Set management fee to 5%
        Fees memory newFees = Fees({
            performanceFee: 0,
            managementFee: 0.05e18,
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(newFees);

        // Warp forward so fees can accrue
        vm.warp(block.timestamp + 365.25 days);

        // Make a withdrawal which should trigger fee taking
        vm.startPrank(alice);
        asyncVault.approve(address(asyncVault), 50e18);
        asyncVault.requestRedeem(50e18, alice, alice);
        asyncVault.fulfillRedeem(50e18, alice);
        asyncVault.withdraw(50e18, alice, alice);
        vm.stopPrank();

        // Check that fees were taken and sent to fee recipient
        assertGt(asyncVault.balanceOf(feeRecipient), 0);
    }

    function testTakeFeesOnSetFees() public virtual {
        // Set initial management fee to 5%
        Fees memory initialFees = Fees({
            performanceFee: 0,
            managementFee: 0.05e18,
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(initialFees);

        // Warp forward so fees can accrue
        vm.warp(block.timestamp + 365.25 days);

        // Set new fees which should trigger fee taking
        Fees memory newFees = Fees({
            performanceFee: 0,
            managementFee: 0.05e18, // Change fee to 5%
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(newFees);

        // Check that fees were taken and sent to fee recipient
        assertGt(asyncVault.balanceOf(feeRecipient), 0);
    }

    function testUpdateFeesHighWatermark() public virtual {
        // Set initial management fee to 5%
        Fees memory initialFees = Fees({
            performanceFee: 0,
            managementFee: 0.05e18,
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(initialFees);

        // Warp forward so fees can accrue
        vm.warp(block.timestamp + 365.25 days);

        vm.prank(owner);
        asyncVault.takeFees();

        Fees memory currentFees = asyncVault.getFees();
        uint256 currentHighWaterMark = currentFees.highWaterMark;

        // high watermark should be higher than share value after fee is taken
        assertGt(currentHighWaterMark, asyncVault.convertToAssets(1e18));
        assertEq(currentHighWaterMark, ONE);

        // fee recipient should have received from management fee
        uint256 feeRecBalance = asyncVault.balanceOf(feeRecipient);
        assertGt(feeRecBalance, 0);

        // Change performance fee to 5%
        initialFees = Fees({
            performanceFee: 0.05e18,
            managementFee: 0.05e18,
            withdrawalIncentive: 0,
            feesUpdatedAt: uint64(block.timestamp),
            feeRecipient: feeRecipient,
            highWaterMark: ONE
        });

        vm.prank(owner);
        asyncVault.setFees(initialFees);

        // no new fees should be taken
        assertEq(feeRecBalance, asyncVault.balanceOf(feeRecipient));

        // high watermark should be the same as before
        Fees memory afterFees = asyncVault.getFees();
        uint256 afterFeesHighWaterMark = afterFees.highWaterMark;

        assertEq(currentHighWaterMark, afterFeesHighWaterMark);

        // Simulate some yield
        asset.mint(address(asyncVault), 100e18);

        // Set new fees which should trigger fee taking
        vm.prank(owner);
        asyncVault.setFees(initialFees);

        // high watermark should be greater now
        afterFees = asyncVault.getFees();
        afterFeesHighWaterMark = afterFees.highWaterMark;
        assertGt(afterFeesHighWaterMark, currentHighWaterMark, "aft");

        // new fees should be taken
        assertLt(feeRecBalance, asyncVault.balanceOf(feeRecipient), "bal");
    }

    // test fees calculation on assets with 6 decimals
    function testPerformanceFeeDecimals() public {
        asset = new MockERC20("Test Token", "TEST", 6);

        InitializeParams memory params = InitializeParams({
            asset: address(asset),
            name: "Vault Token",
            symbol: "vTEST",
            owner: owner,
            limits: Limits({depositLimit: type(uint256).max, minAmount: 0}),
            fees: Fees({
                performanceFee: 1e17, // 10%
                managementFee: 0,
                withdrawalIncentive: 0,
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        asyncVault = new MockAsyncVault(params);

        // Alice deposits 100 USDC
        asset.mint(alice, 100e6);
        vm.startPrank(alice);
        asset.approve(address(asyncVault), 100e6);
        asyncVault.deposit(100e6, alice);
        vm.stopPrank();

        // Simulate some yield
        asset.mint(address(asyncVault), 100e6);

        // no shares before
        assertEq(asyncVault.balanceOf(feeRecipient), 0, "before");

        // take fees
        asyncVault.takeFees();

        assertGt(asyncVault.balanceOf(feeRecipient), 0, "after");
    }

    function testManagementFeeDecimals() public {
        asset = new MockERC20("Test Token", "TEST", 6);

        InitializeParams memory params = InitializeParams({
            asset: address(asset),
            name: "Vault Token",
            symbol: "vTEST",
            owner: owner,
            limits: Limits({depositLimit: type(uint256).max, minAmount: 0}),
            fees: Fees({
                performanceFee: 0,
                managementFee: 0.1e17,
                withdrawalIncentive: 0,
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        asyncVault = new MockAsyncVault(params);

        // Alice deposits 100 USDC
        asset.mint(alice, 100e6);
        vm.startPrank(alice);
        asset.approve(address(asyncVault), 100e6);
        asyncVault.deposit(100e6, alice);
        vm.stopPrank();

        // no fees before
        assertEq(asyncVault.balanceOf(feeRecipient), 0, "before");

        // Warp forward so fees can accrue
        vm.warp(block.timestamp + 365.25 days);

        // take fees
        asyncVault.takeFees();

        // some fees after
        assertGt(asyncVault.balanceOf(feeRecipient), 0, "after");
    }

    /*//////////////////////////////////////////////////////////////
                            LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetLimits() public virtual {
        Limits memory newLimits = Limits({
            depositLimit: 20000e18,
            minAmount: 2e18
        });

        vm.prank(owner);
        asyncVault.setLimits(newLimits);

        (uint256 depositLimit, uint256 minAmount) = asyncVault.limits();
        assertEq(depositLimit, newLimits.depositLimit);
        assertEq(minAmount, newLimits.minAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            BOUNDS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetBounds() public virtual {
        Bounds memory newBounds = Bounds({
            upper: 0.2e18, // 120%
            lower: 0.1e18 // 90%
        });

        vm.prank(owner);
        asyncVault.setBounds(newBounds);

        (uint256 upper, uint256 lower) = asyncVault.bounds();
        assertEq(upper, newBounds.upper);
        assertEq(lower, newBounds.lower);
    }

    function testSetBoundsRevertsNotOwner() public virtual {
        Bounds memory newBounds = Bounds({
            upper: 1.2e18, // 120%
            lower: 0.8e18 // 80%
        });

        vm.prank(alice);
        vm.expectRevert("Owned/not-owner");
        asyncVault.setBounds(newBounds);
    }

    function testSetBoundsRevertsUpperTooHigh() public virtual {
        Bounds memory newBounds = Bounds({
            upper: 1e18, // 100% - too high
            lower: 0.2e18 // 80%
        });

        vm.startPrank(owner);
        vm.expectRevert(AsyncVault.Misconfigured.selector);
        asyncVault.setBounds(newBounds);
        vm.stopPrank();
    }

    function testSetBoundsRevertsLowerTooLow() public virtual {
        Bounds memory newBounds = Bounds({
            upper: 0.2e18, // 120%
            lower: 1e18 // 100% - too high
        });

        vm.startPrank(owner);
        vm.expectRevert(AsyncVault.Misconfigured.selector);
        asyncVault.setBounds(newBounds);
        vm.stopPrank();
    }
}
