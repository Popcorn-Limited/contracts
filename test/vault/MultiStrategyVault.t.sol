// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {MockERC4626} from "../utils/mocks/MockERC4626.sol";
import {MultiStrategyVault, Allocation} from "../../src/vaults/MultiStrategyVault.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {VaultFees} from "../../src/interfaces/vault/IVault.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract MultiStrategyVaultTest is Test {
    using FixedPointMathLib for uint256;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    MockERC20 asset;
    IERC4626[] strategies;
    MultiStrategyVault vault;

    address strategyImplementation;
    address implementation;

    uint256 constant ONE = 1e18;
    uint256 constant SECONDS_PER_YEAR = 365.25 days;

    address feeRecipient = address(0x4444);
    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    event NewFeesProposed(VaultFees newFees, uint256 timestamp);
    event ChangedFees(VaultFees oldFees, VaultFees newFees);
    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);
    event NewStrategiesProposed();
    event ChangedStrategies();
    event QuitPeriodSet(uint256 quitPeriod);
    event Paused(address account);
    event Unpaused(address account);
    event DepositLimitSet(uint256 depositLimit);

    function setUp() public {
        vm.label(feeRecipient, "feeRecipient");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        asset = new MockERC20("Mock Token", "TKN", 18);

        strategyImplementation = address(new MockERC4626());
        implementation = address(new MultiStrategyVault());

        address vaultAddress = Clones.clone(implementation);
        vault = MultiStrategyVault(vaultAddress);
        vm.label(vaultAddress, "vault");

        strategies.push(_createStrategy(IERC20(address(asset))));
        strategies.push(_createStrategy(IERC20(address(asset))));

        vault.initialize(
            IERC20(address(asset)),
            strategies,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );

        uint256[] memory withdrawalQueue = new uint256[](2);
        withdrawalQueue[0] = 0;
        withdrawalQueue[1] = 1;

        vault.setWithdrawalQueue(withdrawalQueue);
    }

    /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

    function _setFees(
        uint64 depositFee,
        uint64 withdrawalFee,
        uint64 managementFee,
        uint64 performanceFee
    ) internal {
        vault.proposeFees(
            VaultFees({
                deposit: depositFee,
                withdrawal: withdrawalFee,
                management: managementFee,
                performance: performanceFee
            })
        );

        vm.warp(block.timestamp + 3 days);
        vault.changeFees();
    }

    function _createStrategy(IERC20 _asset) internal returns (IERC4626) {
        address strategyAddress = Clones.clone(strategyImplementation);
        MockERC4626(strategyAddress).initialize(
            _asset,
            "Mock Token Vault",
            "vwTKN"
        );
        return IERC4626(strategyAddress);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__metadata() public {
        address vaultAddress = Clones.clone(implementation);
        MultiStrategyVault newVault = MultiStrategyVault(vaultAddress);

        uint256 callTime = block.timestamp;
        newVault.initialize(
            IERC20(address(asset)),
            strategies,
            VaultFees({
                deposit: 100,
                withdrawal: 100,
                management: 100,
                performance: 100
            }),
            feeRecipient,
            type(uint256).max,
            bob
        );

        assertEq(newVault.name(), "VaultCraft Mock Token Vault");
        assertEq(newVault.symbol(), "vc-TKN");
        assertEq(newVault.decimals(), 27);

        assertEq(address(newVault.asset()), address(asset));
        assertEq(address(newVault.strategies(0)), address(strategies[0]));
        assertEq(address(newVault.strategies(1)), address(strategies[1]));
        assertEq(newVault.owner(), bob);

        (
            uint256 deposit,
            uint256 withdrawal,
            uint256 management,
            uint256 performance
        ) = newVault.fees();
        assertEq(deposit, 100);
        assertEq(withdrawal, 100);
        assertEq(management, 100);
        assertEq(performance, 100);
        assertEq(newVault.feeRecipient(), feeRecipient);
        assertEq(newVault.highWaterMark(), 1e9);

        assertEq(newVault.quitPeriod(), 3 days);
        assertEq(
            asset.allowance(address(newVault), address(strategies[0])),
            type(uint256).max
        );
        assertEq(
            asset.allowance(address(newVault), address(strategies[1])),
            type(uint256).max
        );
    }

    function testFail__initialize_asset_is_zero() public {
        address vaultAddress = address(new MultiStrategyVault());
        vm.label(vaultAddress, "vault");

        vault = MultiStrategyVault(vaultAddress);
        vault.initialize(
            IERC20(address(0)),
            strategies,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_strategy_asset_is_not_matching() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);

        IERC4626[] memory newStrategies = new IERC4626[](1);
        newStrategies[0] = _createStrategy(IERC20(address(newAsset)));

        address vaultAddress = address(new MultiStrategyVault());

        vault = MultiStrategyVault(vaultAddress);
        vault.initialize(
            IERC20(address(asset)),
            newStrategies,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_strategy_addressZero() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);
        address vaultAddress = address(new MultiStrategyVault());

        vault = MultiStrategyVault(vaultAddress);
        vault.initialize(
            IERC20(address(asset)),
            new IERC4626[](1),
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_fees_too_high() public {
        address vaultAddress = address(new MultiStrategyVault());

        vault = MultiStrategyVault(vaultAddress);
        vault.initialize(
            IERC20(address(asset)),
            strategies,
            VaultFees({
                deposit: 1e18,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );
    }

    function testFail__initialize_feeRecipient_addressZero() public {
        address vaultAddress = address(new MultiStrategyVault());

        vault = MultiStrategyVault(vaultAddress);
        vault.initialize(
            IERC20(address(asset)),
            strategies,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            address(0),
            type(uint256).max,
            address(this)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / WITHDRAW
    //////////////////////////////////////////////////////////////*/

    // TODO -- test withdrawal flow with filled strategies

    function test__deposit_withdraw(uint128 amount) public {
        if (amount < 1e9) amount = 1e9;

        uint256 aliceassetAmount = amount;

        asset.mint(alice, aliceassetAmount);

        vm.prank(alice);
        asset.approve(address(vault), aliceassetAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceassetAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceassetAmount, alice);

        assertEq(
            MockERC4626(address(strategies[0])).afterDepositHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1])).afterDepositHookCalledCounter(),
            0
        );

        // Expect exchange rate to be 1:1e9 on initial deposit.
        assertEq(aliceassetAmount * 1e9, aliceShareAmount);
        assertEq(vault.previewWithdraw(aliceassetAmount), aliceShareAmount);
        assertEq(vault.previewDeposit(aliceassetAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceassetAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceassetAmount
        );
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceassetAmount);

        vm.prank(alice);
        vault.withdraw(aliceassetAmount, alice, alice);

        assertEq(
            MockERC4626(address(strategies[0]))
                .beforeWithdrawHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1]))
                .beforeWithdrawHookCalledCounter(),
            0
        );

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    function testFail__deposit_zero() public {
        vault.deposit(0, address(this));
    }

    function testFail__withdraw_zero() public {
        vault.withdraw(0, address(this), address(this));
    }

    function testFail__deposit_with_no_approval() public {
        vault.deposit(1e18, address(this));
    }

    function testFail__deposit_with_not_enough_approval() public {
        asset.mint(address(this), 1e18);
        asset.approve(address(vault), 0.5e18);
        assertEq(asset.allowance(address(this), address(vault)), 0.5e18);

        vault.deposit(1e18, address(this));
    }

    function testFail__withdraw_with_not_enough_assets() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.withdraw(1e18, address(this), address(this));
    }

    function testFail__withdraw_with_no_assets() public {
        vault.withdraw(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          MINT / REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__mint_redeem(uint128 amount) public {
        if (amount < 1e9) amount = 1e9;

        uint256 aliceShareAmount = amount;
        asset.mint(alice, aliceShareAmount);

        vm.prank(alice);
        asset.approve(address(vault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceAssetAmount = vault.mint(aliceShareAmount, alice);

        assertEq(
            MockERC4626(address(strategies[0])).afterDepositHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1])).afterDepositHookCalledCounter(),
            0
        );

        // Expect exchange rate to be 1e9:1 on initial mint.
        // We allow 1e9 delta since virtual shares lead to amounts between 1e9 to demand/mint more shares
        // E.g. (1e9 + 1) to 2e9 assets requires 2e9 shares to withdraw
        assertApproxEqAbs(
            aliceShareAmount / 1e9,
            aliceAssetAmount,
            1e9,
            "share = assets"
        );
        assertApproxEqAbs(
            vault.previewWithdraw(aliceAssetAmount),
            aliceShareAmount,
            1e9,
            "pw"
        );
        assertApproxEqAbs(
            vault.previewDeposit(aliceAssetAmount),
            aliceShareAmount,
            1e9,
            "pd"
        );
        assertEq(vault.totalSupply(), aliceShareAmount, "ts");
        assertEq(vault.totalAssets(), aliceAssetAmount, "ta");
        assertEq(vault.balanceOf(alice), aliceShareAmount, "bal");
        assertApproxEqAbs(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceAssetAmount,
            1e9,
            "convert"
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceAssetAmount,
            "a bal"
        );

        vm.prank(alice);
        vault.redeem(aliceShareAmount, alice, alice);

        assertEq(
            MockERC4626(address(strategies[0]))
                .beforeWithdrawHookCalledCounter(),
            1
        );
        assertEq(
            MockERC4626(address(strategies[1]))
                .beforeWithdrawHookCalledCounter(),
            0
        );

        assertApproxEqAbs(vault.totalAssets(), 0,1);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertApproxEqAbs(asset.balanceOf(alice), alicePreDepositBal,1);
    }

    function testFail__mint_zero() public {
        vault.mint(0, address(this));
    }

    function testFail__redeem_zero() public {
        vault.redeem(0, address(this), address(this));
    }

    function testFail__mint_with_no_approval() public {
        vault.mint(1e18, address(this));
    }

    function testFail__mint_with_not_enough_approval() public {
        asset.mint(address(this), 1e18);
        asset.approve(address(vault), 1e6);
        assertEq(asset.allowance(address(this), address(vault)), 1e6);

        vault.mint(1e18, address(this));
    }

    function testFail__redeem_with_not_enough_shares() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.redeem(1e27, address(this), address(this));
    }

    function testFail__redeem_with_no_shares() public {
        vault.redeem(1e18, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                DEPOSIT / MINT / WITHDRAW / REDEEM
    //////////////////////////////////////////////////////////////*/

    function test__interactions_for_someone_else() public {
        // init 2 users with a 1e18 balance
        asset.mint(alice, 1e18);
        asset.mint(bob, 1e18);

        vm.prank(alice);
        asset.approve(address(vault), 1e18);

        vm.prank(bob);
        asset.approve(address(vault), 1e18);

        // alice deposits 1e18 for bob
        vm.prank(alice);
        vault.deposit(1e18, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 1e27);
        assertEq(asset.balanceOf(alice), 0);

        // bob mint 1e27 for alice
        vm.prank(bob);
        vault.mint(1e27, alice);
        assertEq(vault.balanceOf(alice), 1e27);
        assertEq(vault.balanceOf(bob), 1e27);
        assertEq(asset.balanceOf(bob), 0);

        // alice redeem 1e27 for bob
        vm.prank(alice);
        vault.redeem(1e27, bob, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 1e27);
        assertEq(asset.balanceOf(bob), 1e18);

        // bob withdraw 1e27 for alice
        vm.prank(bob);
        vault.withdraw(1e18, alice, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), 0);
        assertEq(asset.balanceOf(alice), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                          TAKING FEES
    //////////////////////////////////////////////////////////////*/

    function test__previewDeposit_previewMint_takes_fees_into_account(
        uint8 fuzzAmount
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 1, 1 ether);

        _setFees(1e17, 0, 0, 0);

        asset.mint(alice, amount);

        vm.prank(alice);
        asset.approve(address(vault), amount);

        // Test PreviewDeposit and Deposit
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.prank(alice);
        uint256 actualShares = vault.deposit(amount, alice);
        assertApproxEqAbs(expectedShares, actualShares, 2);
    }

    function test__previewWithdraw_previewRedeem_takes_fees_into_account(
        uint8 fuzzAmount
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 10, 1 ether);

        _setFees(0, 1e17, 0, 0);

        asset.mint(alice, amount);
        asset.mint(bob, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        asset.approve(address(vault), amount);
        vault.deposit(amount, bob);
        vm.stopPrank();

        // Test PreviewWithdraw and Withdraw
        // NOTE: Reduce the amount of assets to withdraw to take withdrawalFee into account (otherwise we would withdraw more than we deposited)
        uint256 withdrawAmount = (amount / 10) * 9;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);
        assertApproxEqAbs(expectedShares, actualShares, 1);

        // Test PreviewRedeem and Redeem
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.prank(bob);
        uint256 actualAssets = vault.redeem(shares, bob, bob);
        assertApproxEqAbs(expectedAssets, actualAssets, 1);
    }

    function test__managementFee(uint128 timeframe) public {
        // Test Timeframe less than 10 years
        timeframe = uint128(bound(timeframe, 1, 315576000));
        uint256 depositAmount = 1 ether;

        _setFees(0, 0, 1e17, 0);

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase Block Time to trigger managementFee
        vm.warp(block.timestamp + timeframe);

        uint256 expectedFeeInAsset = vault.accruedManagementFee();

        uint256 supply = vault.totalSupply();
        uint256 expectedFeeInShares = supply == 0
            ? expectedFeeInAsset
            : expectedFeeInAsset.mulDivDown(
                supply,
                1 ether - expectedFeeInAsset
            );

        vault.takeManagementAndPerformanceFees();

        assertEq(
            vault.totalSupply(),
            (depositAmount * 1e9) + expectedFeeInShares,
            "ts"
        );
        assertEq(vault.balanceOf(feeRecipient), expectedFeeInShares, "fee bal");
        assertApproxEqAbs(
            vault.convertToAssets(expectedFeeInShares),
            expectedFeeInAsset,
            10,
            "convert back"
        );

        // High Water Mark should remain unchanged
        assertEq(vault.highWaterMark(), 1e9, "hwm");
    }

    function test__managementFee_change_fees_later() public {
        uint256 depositAmount = 1 ether;

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Set it to half the time without any fees
        vm.warp(block.timestamp + (SECONDS_PER_YEAR / 2));
        assertEq(vault.accruedManagementFee(), 0);

        _setFees(0, 0, 1e17, 0);

        vm.warp(block.timestamp + (SECONDS_PER_YEAR / 2));

        assertEq(vault.accruedManagementFee(), ((1 ether * 1e17) / 1e18) / 2);
    }

    function test__performanceFee(uint128 amount) public {
        vm.assume(amount >= 1e18);
        uint256 depositAmount = 1 ether;

        _setFees(0, 0, 0, 1e17);

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase asset assets to trigger performanceFee
        asset.mint(address(strategies[0]), amount);

        uint256 expectedFeeInAsset = vault.accruedPerformanceFee();

        uint256 supply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        uint256 expectedFeeInShares = supply == 0
            ? expectedFeeInAsset
            : expectedFeeInAsset.mulDivDown(
                supply,
                totalAssets - expectedFeeInAsset
            );

        vault.takeManagementAndPerformanceFees();

        assertEq(
            vault.totalSupply(),
            (depositAmount * 1e9) + expectedFeeInShares,
            "ts"
        );
        assertEq(vault.balanceOf(feeRecipient), expectedFeeInShares, "bal");

        // There should be a new High Water Mark
        assertApproxEqRel(vault.highWaterMark(), totalAssets / 1e9, 30, "hwm");
    }

    function test_performanceFee2() public {
        address vaultAddress = Clones.clone(implementation);
        vault = MultiStrategyVault(vaultAddress);
        vm.label(vaultAddress, "vault");

        vault.initialize(
            IERC20(address(asset)),
            strategies,
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 1e17
            }),
            feeRecipient,
            type(uint256).max,
            address(this)
        );

        uint256 depositAmount = 1e18;
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        asset.mint(address(strategies[0]), 1e18);

        // Take 10% of 1e18
        assertEq(vault.accruedPerformanceFee(), 1e17 - 1e8);
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE FEES
    //////////////////////////////////////////////////////////////*/

    // Propose Fees
    function test__proposeFees() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });

        uint256 callTime = block.timestamp;
        vm.expectEmit(false, false, false, true, address(vault));
        emit NewFeesProposed(newVaultFees, callTime);

        vault.proposeFees(newVaultFees);

        assertEq(vault.proposedFeeTime(), callTime);
        (
            uint256 deposit,
            uint256 withdrawal,
            uint256 management,
            uint256 performance
        ) = vault.proposedFees();
        assertEq(deposit, 1);
        assertEq(withdrawal, 1);
        assertEq(management, 1);
        assertEq(performance, 1);
    }

    function testFail__proposeFees_nonOwner() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });

        vm.prank(alice);
        vault.proposeFees(newVaultFees);
    }

    function testFail__proposeFees_fees_too_high() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1e18,
            withdrawal: 1,
            management: 1,
            performance: 1
        });

        vault.proposeFees(newVaultFees);
    }

    // Change Fees
    function test__changeFees() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });
        vault.proposeFees(newVaultFees);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(vault));
        emit ChangedFees(
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 0
            }),
            newVaultFees
        );

        vault.changeFees();

        (
            uint256 deposit,
            uint256 withdrawal,
            uint256 management,
            uint256 performance
        ) = vault.fees();
        assertEq(deposit, 1);
        assertEq(withdrawal, 1);
        assertEq(management, 1);
        assertEq(performance, 1);
        (
            uint256 propDeposit,
            uint256 propWithdrawal,
            uint256 propManagement,
            uint256 propPerformance
        ) = vault.proposedFees();
        assertEq(propDeposit, 0);
        assertEq(propWithdrawal, 0);
        assertEq(propManagement, 0);
        assertEq(propPerformance, 0);
        assertEq(vault.proposedFeeTime(), 0);
    }

    function testFail__changeFees_NonOwner() public {
        vm.prank(alice);
        vault.changeFees();
    }

    function testFail__changeFees_respect_rageQuit() public {
        VaultFees memory newVaultFees = VaultFees({
            deposit: 1,
            withdrawal: 1,
            management: 1,
            performance: 1
        });
        vault.proposeFees(newVaultFees);

        // Didnt respect 3 days before propsal and change
        vault.changeFees();
    }

    function testFail__changeFees_after_init() public {
        vault.changeFees();
    }

    /*//////////////////////////////////////////////////////////////
                          SET FEE_RECIPIENT
    //////////////////////////////////////////////////////////////*/

    function test__setFeeRecipient() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit FeeRecipientUpdated(feeRecipient, alice);

        vault.setFeeRecipient(alice);

        assertEq(vault.feeRecipient(), alice);
    }

    function testFail__setFeeRecipient_NonOwner() public {
        vm.prank(alice);
        vault.setFeeRecipient(alice);
    }

    function testFail__setFeeRecipient_addressZero() public {
        vault.setFeeRecipient(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE STRATEGY
    //////////////////////////////////////////////////////////////*/

    // Propose Strategy
    function test__proposeStrategies() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        vm.expectEmit(false, false, false, true, address(vault));
        emit NewStrategiesProposed();

        uint256 callTime = block.timestamp;
        vault.proposeStrategies(newStrategies);

        IERC4626[] memory proposedStrategies = vault.getProposedStrategies();

        assertEq(proposedStrategies.length, 1);
        assertEq(address(proposedStrategies[0]), address(newStrategy));
        assertEq(vault.proposedStrategyTime(), callTime);
    }

    function testFail__proposeStrategies_nonOwner() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        vm.prank(alice);
        vault.proposeStrategies(newStrategies);
    }

    function testFail__proposeStrategies_asset_mismatch() public {
        MockERC20 newAsset = new MockERC20("New Mock Token", "NTKN", 18);
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(newAsset)));
        newStrategies[0] = newStrategy;

        vault.proposeStrategies(newStrategies);
    }

    // Change Strategy
    function test__changeStrategies() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase assets in asset strategy to check hwm and assetCheckpoint later
        asset.mint(address(strategies[0]), depositAmount);
        vault.takeManagementAndPerformanceFees();
        uint256 oldHWM = vault.highWaterMark();

        // Preparation to change the strategies
        vault.proposeStrategies(newStrategies);

        vm.warp(block.timestamp + 3 days);

        vault.changeStrategies();

        assertEq(asset.allowance(address(vault), address(strategies[0])), 0);
        assertEq(asset.allowance(address(vault), address(strategies[1])), 0);

        // Annoyingly Math fails us here and leaves 1 asset in the adapter
        assertEq(asset.balanceOf(address(strategies[0])), 1);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        assertEq(strategies[0].balanceOf(address(vault)), 0);

        assertEq(asset.balanceOf(address(newStrategy)), 0);
        assertEq(asset.balanceOf(address(vault)), (depositAmount * 2) - 1);
        assertEq(
            asset.allowance(address(vault), address(newStrategy)),
            type(uint256).max
        );

        assertEq(vault.highWaterMark(), oldHWM);

        IERC4626[] memory changedStrategies = vault.getStrategies();

        assertEq(changedStrategies.length, 1);
        assertEq(address(changedStrategies[0]), address(newStrategy));

        assertEq(vault.proposedStrategyTime(), 0);
        assertEq(vault.getProposedStrategies().length, 0);
    }

    function testFail__changeStrategies_respect_rageQuit() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        vault.proposeStrategies(newStrategies);

        // Didnt respect 3 days before propsal and change
        vault.changeStrategies();
    }

    function testFail__changeStrategies_after_init() public {
        vault.changeStrategies();
    }

    function testFail__changeStrategies_instantly_again() public {
        IERC4626[] memory newStrategies = new IERC4626[](1);
        IERC4626 newStrategy = _createStrategy(IERC20(address(asset)));
        newStrategies[0] = newStrategy;

        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase assets in asset Adapter to check hwm and assetCheckpoint later
        asset.mint(address(strategies[0]), depositAmount);
        vault.takeManagementAndPerformanceFees();
        uint256 oldHWM = vault.highWaterMark();

        // Preparation to change the adapter
        vault.proposeStrategies(newStrategies);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(vault));
        emit ChangedStrategies();

        vault.changeStrategies();
        vault.changeStrategies();
    }

    function testFail_changeWithdrawalQueue_invalidLength() public {
        uint256[] memory withdrawalQueue = new uint256[](1);
        withdrawalQueue[0] = 0;

        vault.setWithdrawalQueue(withdrawalQueue);
    }

    function testFail_changeWithdrawalQueue_invalidIndex() public {
        uint256[] memory withdrawalQueue = new uint256[](2);
        withdrawalQueue[0] = 5;
        withdrawalQueue[1] = 0;

        vault.setWithdrawalQueue(withdrawalQueue);
    }

    /*//////////////////////////////////////////////////////////////
                          PULL AND PUSH FUNDS
    //////////////////////////////////////////////////////////////*/

    function test_deposit_fundsIdle() public {
        // set default index to be type max 
        vault.setDefaultDepositIndex(type(uint256).max);

        uint256 amount = 1e18;
        _depositIntoVault(bob, amount);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), amount);
    }

    function test_withdrawIdleFunds() public {
         // set default index to be type max 
        vault.setDefaultDepositIndex(type(uint256).max);

        uint256 amount = 1e18;
        _depositIntoVault(bob, amount);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), amount);

        uint256 balBobBefore = asset.balanceOf(bob);

        vm.prank(bob);
        vault.withdraw(amount);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), 0);

        assertEq(asset.balanceOf(bob), balBobBefore + amount);
    }

    function test_withdraw_queueOrder() public {
        _depositIntoVault(bob, 10e18);

        assertEq(asset.balanceOf(address(strategies[0])), 10e18);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 9e18});

        vault.pushFunds(allocations);

        assertEq(asset.balanceOf(address(strategies[1])), 9e18);
        assertEq(asset.balanceOf(address(strategies[0])), 1e18);

        uint256[] memory withdrawalQueue = new uint256[](2);
        withdrawalQueue[0] = 1;
        withdrawalQueue[1] = 0;

        vault.setWithdrawalQueue(withdrawalQueue);

        vm.prank(bob);
        vault.withdraw(95e17);

        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(strategies[0])), 5e17);
    }

    function testFail_setDefaultIndex_invalidIndex() public {
        vault.setDefaultDepositIndex(5);
    }

    function _depositIntoVault(address user, uint256 amount) internal {
        asset.mint(user, amount);

        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function test__pullFunds() public {
        _depositIntoVault(bob, 10e18);

        assertEq(asset.balanceOf(address(strategies[0])), 10e18);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        assertEq(asset.balanceOf(address(strategies[0])), 0);
        assertEq(asset.balanceOf(address(strategies[1])), 0);
        assertEq(asset.balanceOf(address(vault)), 10e18);
    }

    function testFail__pullFunds_noOwner() public {
        _depositIntoVault(bob, 10e18);
        Allocation[] memory allocations = new Allocation[](1);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vm.prank(alice);
        vault.pullFunds(allocations);
    }

    function testFail__pullFunds_indexOutOfBounds() public {
        _depositIntoVault(bob, 10e18);
        Allocation[] memory allocations = new Allocation[](1);
        allocations[0] = Allocation({index: 2, amount: 10e18});

        vault.pullFunds(allocations);
    }

    function testFail__pullFunds_notEnoughFunds() public {
        _depositIntoVault(bob, 10e18);
        Allocation[] memory allocations = new Allocation[](1);
        allocations[0] = Allocation({index: 0, amount: 11e18});

        vault.pullFunds(allocations);
    }

    function test__pushFunds() public {
        _depositIntoVault(bob, 10e18);

        assertEq(asset.balanceOf(address(strategies[0])), 10e18);
        assertEq(asset.balanceOf(address(strategies[1])), 0);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 9e18});

        vault.pushFunds(allocations);

        assertEq(asset.balanceOf(address(strategies[0])), 1e18);
        assertEq(asset.balanceOf(address(strategies[1])), 9e18);
    }

    function testFail__pushFunds_noOwner() public {
        _depositIntoVault(bob, 10e18);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 9e18});

        vm.prank(alice);
        vault.pushFunds(allocations);
    }

    function testFail__pushFunds_indexOutOfBounds() public {
        _depositIntoVault(bob, 10e18);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 2, amount: 9e18});

        vault.pushFunds(allocations);
    }

    function testFail__pushFunds_notEnoughFunds() public {
        _depositIntoVault(bob, 10e18);

        Allocation[] memory allocations = new Allocation[](2);
        allocations[0] = Allocation({index: 0, amount: 10e18});

        vault.pullFunds(allocations);

        allocations[0] = Allocation({index: 0, amount: 1e18});
        allocations[1] = Allocation({index: 1, amount: 10e18});

        vault.pushFunds(allocations);
    }

    /*//////////////////////////////////////////////////////////////
                          SET RAGE QUIT
    //////////////////////////////////////////////////////////////*/

    function test__setQuitPeriod() public {
        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        uint256 newQuitPeriod = 1 days;
        vm.expectEmit(false, false, false, true, address(vault));
        emit QuitPeriodSet(newQuitPeriod);

        vault.setQuitPeriod(newQuitPeriod);

        assertEq(vault.quitPeriod(), newQuitPeriod);
    }

    function testFail__setQuitPeriod_NonOwner() public {
        vm.prank(alice);
        vault.setQuitPeriod(1 days);
    }

    function testFail__setQuitPeriod_too_low() public {
        vault.setQuitPeriod(23 hours);
    }

    function testFail__setQuitPeriod_too_high() public {
        vault.setQuitPeriod(8 days);
    }

    function testFail__setQuitPeriod_during_initial_quitPeriod() public {
        vault.setQuitPeriod(1 days);
    }

    function testFail__setQuitPeriod_during_strategy_quitPeriod() public {
        IERC4626 newAdapter = _createStrategy(IERC20(address(asset)));

        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        vault.proposeStrategies(strategies);

        vault.setQuitPeriod(1 days);
    }

    function testFail__setQuitPeriod_during_fee_quitPeriod() public {
        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        vault.proposeFees(
            VaultFees({
                deposit: 1,
                withdrawal: 1,
                management: 1,
                performance: 1
            })
        );

        vault.setQuitPeriod(1 days);
    }

    /*//////////////////////////////////////////////////////////////
                          SET DEPOSIT LIMIT
    //////////////////////////////////////////////////////////////*/

    function test__setDepositLimit() public {
        uint256 newDepositLimit = 100;
        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositLimitSet(newDepositLimit);

        vault.setDepositLimit(newDepositLimit);

        assertEq(vault.depositLimit(), newDepositLimit);

        asset.mint(address(this), 101);
        asset.approve(address(vault), 101);

        vm.expectRevert(
            abi.encodeWithSelector(MultiStrategyVault.MaxError.selector, 101)
        );
        vault.deposit(101, address(this));

        vm.expectRevert(
            abi.encodeWithSelector(MultiStrategyVault.MaxError.selector, 101)
        );
        vault.mint(101 * 1e9, address(this));
    }

    function testFail__setDepositLimit_NonOwner() public {
        vm.prank(alice);
        vault.setDepositLimit(uint256(100));
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSE
    //////////////////////////////////////////////////////////////*/

    // Pause
    function test__pause() public {
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount * 3);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount * 3);
        vault.deposit(depositAmount * 2, alice);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(vault));
        emit Paused(address(this));

        vault.pause();

        assertTrue(vault.paused());

        vm.prank(alice);
        vm.expectRevert(0xd93c0665); // EnforcedPause()
        vault.deposit(depositAmount, alice);

        vm.prank(alice);
        vm.expectRevert(0xd93c0665); // EnforcedPause()
        vault.mint(depositAmount, alice);

        vm.prank(alice);
        vault.withdraw(depositAmount, alice, alice);

        vm.prank(alice);
        vault.redeem(depositAmount, alice, alice);
    }

    function testFail__pause_nonOwner() public {
        vm.prank(alice);
        vault.pause();
    }

    // Unpause
    function test__unpause() public {
        uint256 depositAmount = 1 ether;

        // Deposit funds for testing
        asset.mint(alice, depositAmount * 2);
        vm.prank(alice);
        asset.approve(address(vault), depositAmount * 2);

        vault.pause();

        vm.expectEmit(false, false, false, true, address(vault));
        emit Unpaused(address(this));

        vault.unpause();

        assertFalse(vault.paused());

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(alice);
        vault.mint(depositAmount, alice);

        vm.prank(alice);
        vault.withdraw(depositAmount, alice, alice);

        vm.prank(alice);
        vault.redeem(depositAmount, alice, alice);
    }

    function testFail__unpause_nonOwner() public {
        vault.pause();

        vm.prank(alice);
        vault.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/

    function test_permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    vault.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            owner,
                            address(0xCAFE),
                            1e18,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vault.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(vault.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(vault.nonces(owner), 1);
    }
}
