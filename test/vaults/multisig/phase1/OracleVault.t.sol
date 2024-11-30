// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {console, console2} from "forge-std/Test.sol";
import {AsyncVaultTest, MockControlledAsyncRedeem, MockERC7540} from "./AsyncVault.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {OracleVault} from "src/vaults/multisig/phase1/OracleVault.sol";
import {AsyncVault, InitializeParams, Limits, Fees, Bounds} from "src/vaults/multisig/phase1/AsyncVault.sol";
import {RequestBalance} from "src/vaults/multisig/phase1/BaseControlledAsyncRedeem.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract OracleVaultTest is AsyncVaultTest {
    using FixedPointMathLib for uint256;

    OracleVault vault;
    MockOracle oracle;

    address safe = address(0x6);

    function setUp() public override {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(safe, "safe");

        asset = new MockERC20("Test Token", "TEST", 18);
        oracle = new MockOracle();

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

        vault = new OracleVault(params, address(oracle), safe);

        // For inherited tests
        asyncVault = MockERC7540(address(vault));
        baseVault = MockControlledAsyncRedeem(address(asyncVault));
        assetReceiver = safe;

        // Setup initial state
        oracle.setPrice(address(vault), address(asset), 1e18);

        asset.mint(alice, INITIAL_DEPOSIT * 2);

        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(INITIAL_DEPOSIT, alice);
        vm.stopPrank();

        vm.prank(safe);
        asset.approve(address(vault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstruction() public {
        assertEq(address(vault.oracle()), address(oracle));
        assertEq(vault.safe(), safe);
    }

    function testConstructionWithZeroMultisig() public {
        InitializeParams memory params = InitializeParams({
            asset: address(asset),
            name: "Vault Token",
            symbol: "vTEST",
            owner: owner,
            limits: Limits({depositLimit: 10000e18, minAmount: 1e18}),
            fees: Fees({
                performanceFee: 1e17,
                managementFee: 1e16,
                withdrawalIncentive: 1e16,
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        vm.expectRevert(AsyncVault.Misconfigured.selector);
        new OracleVault(params, address(oracle), address(0));
    }

    function testConstructionWithZeroOracle() public {
        InitializeParams memory params = InitializeParams({
            asset: address(asset),
            name: "Vault Token",
            symbol: "vTEST",
            owner: owner,
            limits: Limits({depositLimit: 10000e18, minAmount: 1e18}),
            fees: Fees({
                performanceFee: 1e17,
                managementFee: 1e16,
                withdrawalIncentive: 1e16,
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        vm.expectRevert(AsyncVault.Misconfigured.selector);
        new OracleVault(params, address(0), safe);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testTotalAssets() public {
        // Set oracle price to 2:1 (2 assets per share)
        oracle.setPrice(address(vault), address(asset), 2e18);

        uint256 expectedAssets = vault.totalSupply().mulDivDown(2e18, ONE);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDepositWithDifferentPrice() public {
        uint256 depositAmount = INITIAL_DEPOSIT;
        asset.mint(bob, depositAmount);

        // Update price
        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        vm.startPrank(bob);
        asset.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, bob);
        vm.stopPrank();

        // Should receive fewer shares since each share is worth more assets
        assertEq(shares, depositAmount / 2);
        assertEq(vault.balanceOf(bob), shares);
    }

    function testMintWithDifferentPrice() public {
        uint256 mintAmount = INITIAL_DEPOSIT;
        asset.mint(bob, mintAmount * 2);

        // Update price
        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        vm.startPrank(bob);
        asset.approve(address(vault), mintAmount * 2);
        uint256 assets = vault.mint(mintAmount, bob);
        vm.stopPrank();

        // Should receive fewer shares since each share is worth more assets
        assertEq(assets, mintAmount * 2);
        assertEq(vault.balanceOf(bob), mintAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL / REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testWithdraw() public override {
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
        uint256 shares = baseVault.withdraw(assets, bob, alice);

        assertEq(shares, redeemAmount);
        assertEq(asset.balanceOf(bob), assets);
    }

    function testRedeem() public override {
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
        uint256 assets = baseVault.redeem(redeemAmount, bob, alice);

        assertEq(assets, redeemAmount);
        assertEq(asset.balanceOf(bob), assets);
    }

    function testRedeem_issueM01() public override {
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
        oracle.setPrice(address(baseVault), address(asset), 1.1e18);
        asset.mint(address(assetReceiver), 10e18);

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

    /*//////////////////////////////////////////////////////////////
                        FULFILL REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testFulfillRedeem() public override {
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
        assertEq(balance.pendingShares, 0);
        assertEq(balance.claimableShares, redeemAmount);
        assertEq(balance.claimableAssets, assets);
        vm.stopPrank();

        assertEq(asset.balanceOf(assetReceiver), 0);
        assertEq(asset.balanceOf(address(vault)), redeemAmount);
    }

    function testFulfillMultipleRedeems() public override {
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

        assertEq(asset.balanceOf(assetReceiver), redeemAmount);
        assertEq(asset.balanceOf(address(vault)), redeemAmount * 2);
    }

    function testFulfillRedeemWithWithdrawalFee() public override {
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
        assertEq(asset.balanceOf(assetReceiver), 0);
        assertEq(asset.balanceOf(feeRecipient), 1e18);
    }

    function testFulfillRedeemWithLowerBound() public override {
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
    }

    /*//////////////////////////////////////////////////////////////
                            FEES TESTS
    //////////////////////////////////////////////////////////////*/

    function testAccruedFees() public override {
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
        oracle.setPrice(address(vault), address(asset), 2e18);
        uint256 totalFees = asyncVault.accruedFees();
        // Should be management fee (5e18) plus performance fee (15% of 100e18 profit = 15e18)
        assertEq(totalFees, 25e18);
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE PRICE IMPACT TESTS
    //////////////////////////////////////////////////////////////*/

    function testPriceImpactOnConversions() public {
        // Set initial deposit (on first deposit assets and shares are handled 1:1)
        vm.prank(alice);
        vault.deposit(INITIAL_DEPOSIT, alice);

        // Test with different oracle prices
        uint256[] memory prices = new uint256[](3);
        prices[0] = 0.5e18; // 0.5 assets per share
        prices[1] = 1e18; // 1:1
        prices[2] = 2e18; // 2 assets per share

        uint256 amount = INITIAL_DEPOSIT;

        for (uint256 i = 0; i < prices.length; i++) {
            oracle.setPrice(address(vault), address(asset), prices[i]);

            uint256 assets = vault.convertToAssets(amount);
            uint256 shares = vault.convertToShares(amount);

            assertEq(assets, amount.mulDivDown(prices[i], ONE));
            assertEq(shares, amount.mulDivDown(ONE, prices[i]));
        }
    }

    function testPriceImpactOnMaxOperations() public {
        vm.prank(owner);
        vault.setLimits(Limits({depositLimit: 10000e18, minAmount: 1e18}));

        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        (uint256 depositLimit, uint256 minAmount) = vault.limits();
        uint256 currentAssets = vault.totalAssets();

        uint256 maxDeposit = vault.maxDeposit(alice);
        uint256 maxMint = vault.maxMint(alice);

        assertEq(maxDeposit, depositLimit - currentAssets);
        assertEq(maxMint, vault.convertToShares(maxDeposit));
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullDepositWithdrawCycle() public {
        uint256 amount = INITIAL_DEPOSIT;

        // Request withdrawal
        vm.startPrank(alice);
        vault.approve(address(vault), amount);
        uint256 requestId = vault.requestRedeem(amount, alice, alice);
        vm.stopPrank();

        // Oracle price changes
        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        // Fulfill redemption
        asset.mint(safe, amount);
        vm.prank(owner);
        uint256 assets = vault.fulfillRedeem(amount, alice);

        // Final withdrawal
        vm.prank(alice);
        vault.withdraw(assets, bob, alice);

        // Verify final state
        assertEq(vault.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), amount * 2); // Should get more assets due to price increase
    }

    /*//////////////////////////////////////////////////////////////
                        FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateFeesHighWatermark() public override {
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

        assertEq(currentHighWaterMark, asyncVault.convertToAssets(1e18));
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
        oracle.setPrice(address(vault), address(asset), 1.1e18);

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
}
