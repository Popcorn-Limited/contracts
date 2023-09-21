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
    IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20
} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {
    AdapterConfig, ProtocolConfig
} from "../../../../src/vault/v2/base/BaseAdapter.sol";
import "forge-std/Console.sol";

abstract contract BaseVaultTest is Test {

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

}
