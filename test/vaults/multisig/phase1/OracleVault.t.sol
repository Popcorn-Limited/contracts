// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockOracle} from "test/mocks/MockOracle.sol";
import {OracleVault} from "src/vaults/multisig/phase1/OracleVault.sol";
import {AsyncVault, InitializeParams, Limits, Fees, Bounds} from "src/vaults/multisig/phase1/AsyncVault.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract OracleVaultTest is Test {
    using FixedPointMathLib for uint256;

    OracleVault vault;
    MockERC20 asset;
    MockERC20 share;
    MockOracle oracle;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address multisig = address(0x4);
    address feeRecipient = address(0x5);

    uint256 constant INITIAL_DEPOSIT = 100e18;
    uint256 constant ONE = 1e18;

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(multisig, "multisig");

        asset = new MockERC20("Test Token", "TEST", 18);
        share = new MockERC20("Share Token", "SHARE", 18);
        oracle = new MockOracle();

        InitializeParams memory params = InitializeParams({
            asset: address(asset),
            name: "Vault Token",
            symbol: "vTEST",
            owner: owner,
            limits: Limits({depositLimit: 10000e18, minAmount: 1e18}),
            fees: Fees({
                performanceFee: 1e17, // 10%
                managementFee: 1e16, // 1%
                withdrawalIncentive: 0, // 0%
                feesUpdatedAt: uint64(block.timestamp),
                highWaterMark: ONE,
                feeRecipient: feeRecipient
            })
        });

        vault = new OracleVault(params, address(oracle), multisig);

        // Set initial oracle price (1:1 for simplicity)
        oracle.setPrice(address(vault), address(asset), 1e18);

        asset.mint(alice, INITIAL_DEPOSIT);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testInitialization() public {
        assertEq(address(vault.oracle()), address(oracle));
        assertEq(vault.multisig(), multisig);
    }

    function testInitializationWithZeroMultisig() public {
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

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testTotalAssets() public {
        // Set oracle price to 2:1 (2 assets per share)
        oracle.setPrice(address(vault), address(asset), 2e18);

        uint256 expectedAssets = vault.totalSupply().mulDivDown(2e18, ONE);
        assertEq(vault.totalAssets(), expectedAssets);
    }

    function testTotalAssetsWithZeroPrice() public {
        oracle.setPrice(address(vault), address(asset), 0);
        assertEq(vault.totalAssets(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeposit() public {
        uint256 depositAmount = INITIAL_DEPOSIT;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(asset.balanceOf(multisig), depositAmount);
    }

    function testDepositWithDifferentPrice() public {
        uint256 depositAmount = INITIAL_DEPOSIT;

        // Create an initial deposit
        asset.mint(owner, depositAmount);
        vm.startPrank(owner);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, owner);
        vm.stopPrank();

        // Update price
        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Should receive fewer shares since each share is worth more assets
        assertEq(shares, depositAmount / 2);
        assertEq(vault.balanceOf(alice), shares);
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
        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        (uint256 depositLimit, uint256 minAmount) = vault.limits();
        uint256 currentAssets = vault.totalAssets();

        uint256 maxDeposit = vault.maxDeposit(alice);
        uint256 maxMint = vault.maxMint(alice);

        assertEq(maxDeposit, depositLimit - currentAssets);
        assertEq(maxMint, vault.convertToShares(maxDeposit));
    }

    /*//////////////////////////////////////////////////////////////
                        MULTISIG TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testAssetTransferToMultisig() public {
        uint256 depositAmount = INITIAL_DEPOSIT;

        uint256 multisigBalanceBefore = asset.balanceOf(multisig);

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        assertEq(
            asset.balanceOf(multisig),
            multisigBalanceBefore + depositAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullDepositWithdrawCycle() public {
        uint256 depositAmount = INITIAL_DEPOSIT;

        // Initial deposit
        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // Request withdrawal
        vault.approve(address(vault), shares);
        uint256 requestId = vault.requestRedeem(shares, alice, alice);
        vm.stopPrank();

        // Oracle price changes
        oracle.setPrice(address(vault), address(asset), 2e18); // 2 assets per share

        // Prepare fulfillment
        asset.mint(multisig, depositAmount); // now the multisig controls 2 * depositAmount
        vm.prank(multisig);
        asset.approve(address(vault), depositAmount * 2);

        // Fulfill redemption
        vm.prank(owner);
        uint256 assets = vault.fulfillRedeem(shares, alice);

        // Final withdrawal
        vm.prank(alice);
        vault.withdraw(assets, alice, alice);

        // Verify final state
        assertEq(vault.balanceOf(alice), 0);
        assertGt(asset.balanceOf(alice), depositAmount); // Should get more assets due to price increase
    }
}
