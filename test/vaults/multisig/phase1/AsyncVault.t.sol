// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {AsyncVault, InitializeParams, Limits, Fees, Bounds} from "src/vaults/multisig/phase1/AsyncVault.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract MockAsyncVault is AsyncVault {
    constructor(
        InitializeParams memory params
    ) AsyncVault(params) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract AsyncVaultTest is Test {
    using FixedPointMathLib for uint256;

    MockAsyncVault vault;
    MockERC20 asset;
    
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address feeRecipient = address(0x4);

    uint256 constant INITIAL_DEPOSIT = 1000e18;
    uint256 constant ONE = 1e18;

    event FeesUpdated(Fees prev, Fees next);
    event LimitsUpdated(Limits prev, Limits next);

    function setUp() public {
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
            limits: Limits({
                depositLimit: 10000e18,
                minAmount: 1e18
            }),
            fees: Fees({
                performanceFee: 1e17, // 10%
                managementFee: 1e16,  // 1%
                withdrawalIncentive: 1e16, // 1%
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        vault = new MockAsyncVault(params);

        // Setup initial state
        asset.mint(alice, INITIAL_DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testPreviewDeposit() public {
        uint256 depositAmount = 100e18;
        uint256 expectedShares = vault.convertToShares(depositAmount);
        assertEq(vault.previewDeposit(depositAmount), expectedShares);
    }

    function testPreviewDepositBelowMin() public {
        uint256 depositAmount = 0.5e18;
        assertEq(vault.previewDeposit(depositAmount), 0);
    }

    function testPreviewMint() public {
        uint256 mintAmount = 100e18;
        uint256 expectedAssets = vault.convertToAssets(mintAmount);
        assertEq(vault.previewMint(mintAmount), expectedAssets);
    }

    function testPreviewMintBelowMin() public {
        uint256 mintAmount = 0.5e18;
        assertEq(vault.previewMint(mintAmount), 0);
    }

    function testConvertToLowBoundAssets() public {
        // Set bounds
        Bounds memory bounds = Bounds({
            upper: 1.1e18, // 110%
            lower: 0.9e18  // 90%
        });
        vm.prank(owner);
        vault.setBounds(bounds);

        uint256 shares = 100e18;
        uint256 expectedAssets = vault.totalAssets().mulDivDown(bounds.lower, 1e18);
        uint256 expectedShares = shares.mulDivDown(expectedAssets, vault.totalSupply());
        
        assertEq(vault.convertToLowBoundAssets(shares), expectedShares);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMaxDeposit() public {
        uint256 depositLimit = vault.limits().depositLimit;
        uint256 currentAssets = vault.totalAssets();
        assertEq(vault.maxDeposit(alice), depositLimit - currentAssets);
    }

    function testMaxDepositWhenPaused() public {
        vm.prank(owner);
        vault.pause();
        assertEq(vault.maxDeposit(alice), 0);
    }

    function testMaxMint() public {
        uint256 depositLimit = vault.limits().depositLimit;
        uint256 currentAssets = vault.totalAssets();
        uint256 expectedShares = vault.convertToShares(depositLimit - currentAssets);
        assertEq(vault.maxMint(alice), expectedShares);
    }

    function testMaxMintWhenPaused() public {
        vm.prank(owner);
        vault.pause();
        assertEq(vault.maxMint(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit() public {
        uint256 depositAmount = 100e18;
        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), INITIAL_DEPOSIT + shares);
        vm.stopPrank();
    }

    function testMint() public {
        uint256 mintAmount = 100e18;
        vm.startPrank(alice);
        uint256 assets = vault.mint(mintAmount);
        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), INITIAL_DEPOSIT + mintAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRedeem() public {
        uint256 redeemAmount = 100e18;
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        uint256 requestId = vault.requestRedeem(redeemAmount, alice, alice);
        assertGt(requestId, 0);
        vm.stopPrank();
    }

    function testRequestRedeemBelowMin() public {
        uint256 redeemAmount = 0.5e18;
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        vm.expectRevert("ERC7540Vault/min-amount");
        vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();
    }

    function testFulfillRedeem() public {
        uint256 redeemAmount = 100e18;
        
        // Setup redeem request
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount);
        uint256 requestId = vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        // Fulfill request
        vm.startPrank(owner);
        uint256 assets = vault.fulfillRedeem(redeemAmount, alice);
        assertGt(assets, 0);
        vm.stopPrank();
    }

    function testFulfillMultipleRedeems() public {
        uint256 redeemAmount = 100e18;
        
        // Setup redeem requests
        vm.startPrank(alice);
        vault.approve(address(vault), redeemAmount * 2);
        uint256 request1 = vault.requestRedeem(redeemAmount, alice, alice);
        uint256 request2 = vault.requestRedeem(redeemAmount, alice, alice);
        vm.stopPrank();

        uint256[] memory shares = new uint256[](2);
        shares[0] = redeemAmount;
        shares[1] = redeemAmount;

        address[] memory controllers = new address[](2);
        controllers[0] = alice;
        controllers[1] = alice;

        vm.prank(owner);
        uint256 totalAssets = vault.fulfillMultipleRedeems(shares, controllers);
        assertGt(totalAssets, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function testAccruedFees() public {
        // Simulate some yield
        asset.mint(address(vault), 100e18);
        
        vm.warp(block.timestamp + 365 days);
        
        uint256 fees = vault.accruedFees();
        assertGt(fees, 0);
    }

    function testSetFees() public {
        Fees memory newFees = Fees({
            performanceFee: 0.15e18, // 15%
            managementFee: 0.02e18,  // 2%
            withdrawalIncentive: 0.02e18, // 2%
            feesUpdatedAt: uint64(block.timestamp),
            highWaterMark: ONE,
            feeRecipient: feeRecipient
        });

        vm.prank(owner);
        vault.setFees(newFees);

        Fees memory currentFees = vault.fees();
        assertEq(currentFees.performanceFee, newFees.performanceFee);
        assertEq(currentFees.managementFee, newFees.managementFee);
        assertEq(currentFees.withdrawalIncentive, newFees.withdrawalIncentive);
    }

    function testSetFeesRevertsTooHigh() public {
        Fees memory newFees = Fees({
            performanceFee: 0.3e18, // 30% - too high
            managementFee: 0.02e18,
            withdrawalIncentive: 0.02e18,
            feesUpdatedAt: uint64(block.timestamp),
            highWaterMark: ONE,
            feeRecipient: feeRecipient
        });

        vm.prank(owner);
        vm.expectRevert(AsyncVault.Misconfigured.selector);
        vault.setFees(newFees);
    }

    function testTakeFees() public {
        // Simulate some yield
        asset.mint(address(vault), 100e18);
        
        vm.warp(block.timestamp + 365 days);
        
        uint256 feeRecipientBalanceBefore = vault.balanceOf(feeRecipient);
        
        vm.prank(owner);
        vault.takeFees();
        
        assertGt(vault.balanceOf(feeRecipient), feeRecipientBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                            LIMIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetLimits() public {
        Limits memory newLimits = Limits({
            depositLimit: 20000e18,
            minAmount: 2e18
        });

        vm.prank(owner);
        vault.setLimits(newLimits);

        Limits memory currentLimits = vault.limits();
        assertEq(currentLimits.depositLimit, newLimits.depositLimit);
        assertEq(currentLimits.minAmount, newLimits.minAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            BOUNDS TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetBounds() public {
        Bounds memory newBounds = Bounds({
            upper: 1.2e18, // 120%
            lower: 0.8e18  // 80%
        });

        vm.prank(owner);
        vault.setBounds(newBounds);

        Bounds memory currentBounds = vault.bounds();
        assertEq(currentBounds.upper, newBounds.upper);
        assertEq(currentBounds.lower, newBounds.lower);
    }
}