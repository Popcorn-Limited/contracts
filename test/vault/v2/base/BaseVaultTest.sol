// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../../../utils/mocks/MockERC20.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { MockStrategyV2 } from "../../../utils/mocks/MockStrategyV2.sol";
import { IVault } from "../../../../src/vault/v2/base/interfaces/IVault.sol";
import { BaseVaultConfig, BaseVault, VaultFees } from "../../../../src/vault/v2/base/BaseVault.sol";
import {
    IERC20Upgradeable as IERC20,
    IERC4626Upgradeable as IERC4626
} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {
    AdapterConfig, ProtocolConfig
} from "../../../../src/vault/v2/base/BaseAdapter.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import "forge-std/Console.sol";

abstract contract BaseVaultTest is Test {
    using FixedPointMathLib for uint256;

    IVault public vault;
    MockERC20 public asset;
    MockStrategyV2 public adapter;
    address public vaultImplementation;
    address public adapterImplementation;

    address public bob = address(0xDCBA);
    address public alice = address(0xABCD);
    address public feeRecipient = address(0x4444);

    function setUp() public virtual {
        vm.label(feeRecipient, "feeRecipient");
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        asset = new MockERC20("Mock Token", "TKN", 18);

        adapter = _createAdapter();
        vm.label(address(adapter), "adapter");

        vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            _getVaultConfig(),
            address(adapter)
        );
        adapter.addVault(address(vault));
    }


    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/
    function _createAdapter() internal virtual returns (MockStrategyV2);

    function _createVault() internal virtual returns (IVault);

    function _getVaultConfig() internal virtual returns(BaseVaultConfig memory);

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

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function testFail__initialize_strategy_addressZero() public {
        IVault vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            _getVaultConfig(),
            address(0)
        );
    }

    function testFail__initialize_asset_is_zero() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        vaultConfig.asset_ = IERC20(address(0));

        IVault vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            vaultConfig,
            address(adapter)
        );
    }

    function testFail__initialize_invalid_vault_fees() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        vaultConfig.fees.deposit = 1e19;
        vaultConfig.fees.management = 1e19;
        vaultConfig.fees.withdrawal = 1e19;
        vaultConfig.fees.performance = 1e19;

        IVault vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            vaultConfig,
            address(adapter)
        );
    }

    function testFail__initialize_invalid_fee_recipient() public {
        BaseVaultConfig memory vaultConfig = _getVaultConfig();
        vaultConfig.feeRecipient = address(0);

        IVault vault = _createVault();
        vm.label(address(vault), "vault");

        vault.initialize(
            vaultConfig,
            address(adapter)
        );
    }

    function test__metadata() public {
        IVault newVault = _createVault();

        uint256 callTime = block.timestamp;
        newVault.initialize(
            _getVaultConfig(),
            address(adapter)
        );

        assertEq(newVault.name(), _getVaultConfig().name);
        assertEq(newVault.symbol(), "vc-TKN");
        assertEq(newVault.decimals(), 27);

        assertEq(address(newVault.asset()), address(asset));
        assertEq(address(newVault.strategy()), address(adapter));
        assertEq(newVault.owner(), bob);

        VaultFees memory vaultFees = newVault.fees();
        VaultFees memory expectedVaultFees = _getVaultConfig().fees;

        assertEq(vaultFees.deposit, expectedVaultFees.deposit);
        assertEq(vaultFees.withdrawal, expectedVaultFees.withdrawal);
        assertEq(vaultFees.management, expectedVaultFees.management);
        assertEq(vaultFees.performance, expectedVaultFees.performance);
        assertEq(newVault.feeRecipient(), feeRecipient);
        assertEq(newVault.highWaterMark(), 1e9);

        assertEq(newVault.quitPeriod(), 3 days);
        assertEq(asset.allowance(address(newVault), address(adapter)), type(uint256).max);
    }


    /*//////////////////////////////////////////////////////////////
                       DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/
    function testFail__deposit_zero() public {
        vault.deposit(0, address(this));
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

    function test__deposit(uint128 fuzzAmount) public {
        uint256 aliceAssetAmount = bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);

        asset.mint(alice, aliceAssetAmount);

        vm.prank(alice);
        asset.approve(address(vault), aliceAssetAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceAssetAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceAssetAmount, alice);

        assertEq(aliceAssetAmount, aliceShareAmount);
        assertEq(vault.previewDeposit(aliceAssetAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceAssetAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceAssetAmount);
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceAssetAmount);
    }

    /*//////////////////////////////////////////////////////////////
                       WITHDRAW LOGIC
    //////////////////////////////////////////////////////////////*/
    function testFail__withdraw_with_no_assets() public {
        vault.withdraw(1e18, address(this), address(this));
    }

    function testFail__withdraw_with_not_enough_assets() public {
        vault.withdraw(1e18, address(this), address(this));
    }

    function test__withdraw(uint128 fuzzAmount) public {
        uint256 aliceAssetAmount = bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);

        asset.mint(alice, aliceAssetAmount);
        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        asset.approve(address(vault), aliceAssetAmount);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceAssetAmount, alice);

        assertEq(vault.previewWithdraw(aliceAssetAmount), aliceShareAmount);

        vm.prank(alice);
        vault.withdraw(aliceAssetAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    /*//////////////////////////////////////////////////////////////
                       MINT LOGIC
    //////////////////////////////////////////////////////////////*/
    function testFail__mint_zero() public {
        vault.mint(0, address(this));
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

    function test__mint(uint256 fuzzAmount) public {
        uint256 aliceShareAmount = bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);
        asset.mint(alice, aliceShareAmount);
        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        asset.approve(address(vault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceShareAmount);


        vm.prank(alice);
        uint256 aliceAssetAmount = vault.mint(aliceShareAmount, alice);
        assertEq(aliceShareAmount, aliceAssetAmount);
        assertEq(vault.previewWithdraw(aliceAssetAmount), aliceShareAmount);
        assertEq(vault.previewDeposit(aliceAssetAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceAssetAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceAssetAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceAssetAmount);
    }

    /*//////////////////////////////////////////////////////////////
                     REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/
    function testFail__redeem_zero() public {
        vault.redeem(0, address(this), address(this));
    }

    function testFail__redeem_with_no_shares() public {
        vault.redeem(1e18, address(this), address(this));
    }

    function testFail__redeem_with_not_enough_shares() public {
        asset.mint(address(this), 0.5e18);
        asset.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.redeem(1e27, address(this), address(this));
    }

    function test__redeem(uint256 fuzzAmount) public {
        uint256 aliceShareAmount = bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);
        asset.mint(alice, aliceShareAmount);
        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        asset.approve(address(vault), aliceShareAmount);

        vm.prank(alice);
        uint256 aliceAssetAmount = vault.mint(aliceShareAmount, alice);

        vm.prank(alice);
        vault.redeem(aliceShareAmount, alice, alice);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    /*//////////////////////////////////////////////////////////////
                     PREVIEW LOGIC WITH FEES
    //////////////////////////////////////////////////////////////*/
    function test__preview_deposit_with_deposit_fee(uint8 fuzzAmount) public {
        uint256 amount = bound(uint256(fuzzAmount), 1, _getVaultConfig().depositLimit);
        uint64 depositFee = uint64(_getVaultConfig().depositLimit / 10);
        vm.prank(bob);
        _setFees(depositFee, 0, 0, 0);

        asset.mint(alice, amount);

        vm.prank(alice);
        asset.approve(address(vault), amount);

        // Test PreviewDeposit and Deposit
        uint256 expectedShares = vault.previewDeposit(amount);

        vm.prank(alice);
        uint256 actualShares = vault.deposit(amount, alice);
        assertApproxEqAbs(expectedShares, actualShares, 2);
    }

    function test__preview_withdraw_with_withdrawal_fee(uint8 fuzzAmount) public {
        uint256 amount = bound(uint256(fuzzAmount), 100, _getVaultConfig().depositLimit);

        uint64 withdrawalFee = uint64(_getVaultConfig().depositLimit / 10);
        vm.prank(bob);
        _setFees(0, withdrawalFee, 0, 0);

        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, alice);
        vm.stopPrank();

        // Test PreviewWithdraw and Withdraw
        // NOTE: Reduce the amount of assets to withdraw to take withdrawalFee into account (otherwise we would withdraw more than we deposited)
        uint256 withdrawAmount = (amount / 10) * 9;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);
        assertApproxEqAbs(expectedShares, actualShares, 1);
    }

    function test__preview_redeem_with_withdrawal_fee(uint8 fuzzAmount) public {
        uint256 amount = bound(uint256(fuzzAmount), 100, _getVaultConfig().depositLimit);

        uint64 withdrawalFee = uint64(_getVaultConfig().depositLimit / 10);
        vm.prank(bob);
        _setFees(0, withdrawalFee, 0, 0);

        asset.mint(bob, amount);

        vm.startPrank(bob);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, bob);
        vm.stopPrank();

        // Test PreviewRedeem and Redeem
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.prank(bob);
        uint256 actualAssets = vault.redeem(shares, bob, bob);
    }

    /*//////////////////////////////////////////////////////////////
                     FEE COLLECTION LOGIC
    //////////////////////////////////////////////////////////////*/
    function test__managementFee(uint128 timeframe) public {
        // Test Timeframe less than 10 years
        timeframe = uint128(bound(timeframe, 1, 315576000));
        uint256 depositAmount = _getVaultConfig().depositLimit;

        vm.prank(bob);
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
            : expectedFeeInAsset.mulDivDown(supply, depositAmount- expectedFeeInAsset);

        vault.takeManagementAndPerformanceFees();
        assertEq(vault.totalSupply(), depositAmount + expectedFeeInShares);
        assertEq(vault.balanceOf(feeRecipient), expectedFeeInShares, "fee bal");

        assertApproxEqAbs(vault.convertToAssets(expectedFeeInShares), expectedFeeInAsset, 10, "convert back");

        // High Water Mark should remain unchanged
        assertEq(vault.highWaterMark(), 1e18, "hwm");
    }

    uint256 constant public SECONDS_PER_YEAR = 365.25 days;
    function test__managementFee_change_fees_later() public {
        uint256 depositAmount = _getVaultConfig().depositLimit;

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Set it to half the time without any fees
        vm.warp(block.timestamp + (SECONDS_PER_YEAR / 2));
        assertEq(vault.accruedManagementFee(), 0);

        vm.prank(bob);
        _setFees(0, 0, 1e17, 0);

        vm.warp(block.timestamp + (SECONDS_PER_YEAR / 2));
        assertEq(vault.accruedManagementFee(), ((depositAmount * 1e17) / 1e18) / 2);
    }

    function test__performanceFee(uint128 amount) public {
        vm.assume(amount >= 1e18);
        uint256 depositAmount = _getVaultConfig().depositLimit;

        vm.prank(bob);
        _setFees(0, 0, 0, 1e17);

        asset.mint(alice, depositAmount);
        vm.startPrank(alice);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Increase asset assets to trigger performanceFee
        asset.mint(address(adapter), amount);

        uint256 expectedFeeInAsset = vault.accruedPerformanceFee(_getVaultConfig().fees.performance);

        uint256 supply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        uint256 expectedFeeInShares = supply == 0
            ? expectedFeeInAsset
            : expectedFeeInAsset.mulDivDown(supply, totalAssets - expectedFeeInAsset);

        vault.takeManagementAndPerformanceFees();
        assertEq(vault.totalSupply(), depositAmount + expectedFeeInShares);
        assertEq(vault.balanceOf(feeRecipient), expectedFeeInShares);

        // There should be a new High Water Mark
        assertApproxEqRel(vault.highWaterMark(), 1e18, 30, "hwm");
    }

    /*//////////////////////////////////////////////////////////////
                          CHANGE FEES
    //////////////////////////////////////////////////////////////*/
    function testFail__proposeFees_nonOwner() public {
        VaultFees memory newVaultFees = VaultFees({ deposit: 1, withdrawal: 1, management: 1, performance: 1 });
        vm.prank(alice);
        vault.proposeFees(newVaultFees);
    }

    function testFail__proposeFees_fees_too_high() public {
        VaultFees memory newVaultFees = VaultFees({ deposit: 1e18, withdrawal: 1, management: 1, performance: 1 });
        vault.proposeFees(newVaultFees);
    }
    function testFail__changeFees_NonOwner() public {
        vm.prank(alice);
        vault.changeFees();
    }

    function testFail__changeFees_respect_rageQuit() public {
        VaultFees memory newVaultFees = VaultFees({ deposit: 1, withdrawal: 1, management: 1, performance: 1 });
        vault.proposeFees(newVaultFees);

        // Didnt respect 3 days before propsal and change
        vault.changeFees();
    }

    function testFail__changeFees_after_init() public {
        vault.changeFees();
    }

    event NewFeesProposed(VaultFees newFees, uint256 timestamp);
    function test__proposeFees() public {
        VaultFees memory newVaultFees = VaultFees({ deposit: 1, withdrawal: 1, management: 1, performance: 1 });

        uint256 callTime = block.timestamp;
        vm.expectEmit(false, false, false, true, address(vault));
        emit NewFeesProposed(newVaultFees, callTime);

        vm.prank(bob);
        vault.proposeFees(newVaultFees);

        assertEq(vault.proposedFeeTime(), callTime);
        VaultFees memory vaultFees = vault.proposedFees();
        assertEq(vaultFees.deposit, 1);
        assertEq(vaultFees.withdrawal, 1);
        assertEq(vaultFees.management, 1);
        assertEq(vaultFees.performance, 1);
    }

    event ChangedFees(VaultFees oldFees, VaultFees newFees);
    function test__changeFees() public {
        VaultFees memory newVaultFees = VaultFees({ deposit: 1, withdrawal: 1, management: 1, performance: 1 });

        vm.prank(bob);
        vault.proposeFees(newVaultFees);

        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(false, false, false, true, address(vault));
        emit ChangedFees(VaultFees({ deposit: 100, withdrawal: 0, management: 100, performance: 100 }), newVaultFees);

        vm.prank(bob);
        vault.changeFees();

        VaultFees memory vaultFees = vault.fees();
        assertEq(vaultFees.deposit, 1);
        assertEq(vaultFees.withdrawal, 1);
        assertEq(vaultFees.management, 1);
        assertEq(vaultFees.performance, 1);

        VaultFees memory proposedVaultFees = vault.proposedFees();

        assertEq(proposedVaultFees.deposit, 0);
        assertEq(proposedVaultFees.withdrawal, 0);
        assertEq(proposedVaultFees.management, 0);
        assertEq(proposedVaultFees.performance, 0);
        assertEq(vault.proposedFeeTime(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          SET FEE_RECIPIENT
    //////////////////////////////////////////////////////////////*/
    function testFail__setFeeRecipient_NonOwner() public {
        vm.prank(alice);
        vault.setFeeRecipient(alice);
    }

    function testFail__setFeeRecipient_addressZero() public {
        vault.setFeeRecipient(address(0));
    }

    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);
    function test__setFeeRecipient() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit FeeRecipientUpdated(feeRecipient, alice);

        vm.prank(bob);
        vault.setFeeRecipient(alice);

        assertEq(vault.feeRecipient(), alice);
    }

    /*//////////////////////////////////////////////////////////////
                          SET RAGE QUIT
    //////////////////////////////////////////////////////////////*/
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

    function testFail__setQuitPeriod_during_fee_quitPeriod() public {
        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);
        vault.proposeFees(VaultFees({ deposit: 1, withdrawal: 1, management: 1, performance: 1 }));
        vault.setQuitPeriod(1 days);
    }

    event QuitPeriodSet(uint256 quitPeriod);
    function test__setQuitPeriod() public {
        // Pass the inital quit period
        vm.warp(block.timestamp + 3 days);

        uint256 newQuitPeriod = 1 days;
        vm.expectEmit(false, false, false, true, address(vault));
        emit QuitPeriodSet(newQuitPeriod);

        vm.prank(bob);
        vault.setQuitPeriod(newQuitPeriod);

        assertEq(vault.quitPeriod(), newQuitPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                         SET DEPOSIT LIMIT
    //////////////////////////////////////////////////////////////*/
    function testFail__setDepositLimit_NonOwner() public {
        vm.prank(alice);
        vault.setDepositLimit(uint256(100));
    }

    event DepositLimitSet(uint256 depositLimit);
    function test__setDepositLimit() public {
        uint256 newDepositLimit = 100;
        vm.expectEmit(false, false, false, true, address(vault));
        emit DepositLimitSet(newDepositLimit);

        vm.prank(bob);
        vault.setDepositLimit(newDepositLimit);

        assertEq(vault.depositLimit(), newDepositLimit);

        asset.mint(address(this), 101);
        asset.approve(address(vault), 101);

        vm.expectRevert(abi.encodeWithSelector(IVault.MaxError.selector, 101));
        vault.deposit(101, address(this));

        vm.expectRevert(abi.encodeWithSelector(IVault.MaxError.selector, 101 * 1e9));
        vault.mint(101 * 1e9, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                              PERMIT
    //////////////////////////////////////////////////////////////*/
    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    function test_permit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    vault.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        vault.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(vault.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(vault.nonces(owner), 1);
    }
}
