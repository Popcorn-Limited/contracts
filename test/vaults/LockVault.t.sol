// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {MockERC4626} from "../utils/mocks/MockERC4626.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {LockVault, Lock} from "src/vaults/LockVault.sol";

contract LockVaultTest is Test {
    LockVault vault;

    MockERC20 asset = new MockERC20("A", "Asset", 18);
    MockERC20 rewardToken1 = new MockERC20("R1", "Reward1", 18);
    MockERC20 rewardToken2 = new MockERC20("R2", "Reward2", 18);

    MockERC20[] rewardTokens;

    MockERC4626 strategy;

    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 MAX_LOCK_TIME = 365 days * 4;

    function setUp() public {
        address adapterImplementation = address(new MockERC4626());
        strategy = MockERC4626(Clones.clone(adapterImplementation));
        strategy.initialize(
            IERC20(address(asset)),
            "Mock Token Vault",
            "vwTKN"
        );

        rewardTokens.push(rewardToken1);
        rewardTokens.push(rewardToken2);

        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = address(rewardToken1);
        _rewardTokens[1] = address(rewardToken2);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            _rewardTokens,
            address(strategy),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                INIT
    //////////////////////////////////////////////////////////////*/

    function test_init() public {
        assertEq(address(vault.asset()), address(asset));
        assertEq(address(vault.strategy()), address(strategy));
        assertEq(vault.MAX_LOCK_TIME(), MAX_LOCK_TIME);

        assertEq(vault.name(), "VaultName");
        assertEq(vault.symbol(), "v");

        assertEq(vault.getRewardLength(), 2);
        assertEq(address(vault.rewardTokens(0)), address(rewardToken1));
        assertEq(address(vault.rewardTokens(1)), address(rewardToken2));
        assertEq(
            asset.allowance(address(vault), address(strategy)),
            type(uint256).max
        );
    }

    function test_init_without_strategy() public {
        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = address(rewardToken1);
        _rewardTokens[1] = address(rewardToken2);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            _rewardTokens,
            address(0),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );

        assertEq(address(vault.strategy()), address(0));
        assertEq(asset.allowance(address(vault), address(strategy)), 0);
    }

    function testFail_init_without_asset() public {
        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = address(rewardToken1);
        _rewardTokens[1] = address(rewardToken2);

        vault = new LockVault();
        vault.initialize(
            address(0),
            _rewardTokens,
            address(strategy),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );
    }

    function testFail_init_without_rewardTokens() public {
        address[] memory _rewardTokens = new address[](0);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            _rewardTokens,
            address(strategy),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );
    }

    function testFail_init_without_maxLockTime() public {
        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = address(rewardToken1);
        _rewardTokens[1] = address(rewardToken2);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            _rewardTokens,
            address(strategy),
            0,
            "VaultName",
            "v"
        );
    }

    function testFail_init_with_empty_rewardToken() public {
        address[] memory rewards = new address[](2);
        rewards[0] = address(rewardToken1);
        rewards[1] = address(0);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            rewards,
            address(strategy),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT / WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function test_deposit(uint256 amount) public {
        vm.assume(amount != 0 && amount <= 100_000e18);
        deal(address(asset), alice, amount);

        uint256 expectedShares = vault.toShares(amount);
        uint256 expectedRewardShares = vault.toRewardShares(
            amount,
            MAX_LOCK_TIME
        );

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(alice, amount, MAX_LOCK_TIME);
        vm.stopPrank();

        (
            uint256 unlockTime,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(alice);
        uint256[] memory rewardIndices = vault.getUserIndices(alice);

        assertEq(
            unlockTime,
            block.timestamp + MAX_LOCK_TIME,
            "wrong unlock time"
        );
        assertEq(rewardIndices[0], vault.currIndices(0), "wrong reward index1");
        assertEq(rewardIndices[1], vault.currIndices(1), "wrong reward index2");

        assertEq(lockAmount, amount, "wrong lock amount");
        assertEq(lockRewardShares, expectedRewardShares, "wrong rewardShares");
        assertEq(shares, expectedShares, "wrong shares");
        assertEq(asset.balanceOf(alice), 0, "wrong asset bal");
        assertEq(
            asset.balanceOf(address(strategy)),
            amount,
            "wrong asset bal strat"
        );
        assertEq(
            strategy.balanceOf(address(vault)),
            amount * 1e9,
            "wrong strat bal in vault"
        );
    }

    function test_deposit_without_strategy(uint256 amount) public {
        vm.assume(amount != 0 && amount <= 100_000e18);
        deal(address(asset), alice, amount);

        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = address(rewardToken1);
        _rewardTokens[1] = address(rewardToken2);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            _rewardTokens,
            address(0),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );

        uint256 expectedShares = vault.toShares(amount);
        uint256 expectedRewardShares = vault.toRewardShares(
            amount,
            MAX_LOCK_TIME
        );

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(alice, amount, MAX_LOCK_TIME);
        vm.stopPrank();

        (
            uint256 unlockTime,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(alice);
        uint256[] memory rewardIndices = vault.getUserIndices(alice);

        assertEq(
            unlockTime,
            block.timestamp + MAX_LOCK_TIME,
            "wrong unlock time"
        );
        assertEq(rewardIndices[0], vault.currIndices(0), "wrong reward index1");
        assertEq(rewardIndices[1], vault.currIndices(1), "wrong reward index2");

        assertEq(lockAmount, amount, "wrong lock amount");
        assertEq(lockRewardShares, expectedRewardShares, "wrong rewardShares");
        assertEq(shares, expectedShares, "wrong shares");
        assertEq(asset.balanceOf(alice), 0, "wrong asset bal");
    }

    function test_deposit_for_others() public {
        uint256 amount = 1e18;
        deal(address(asset), alice, amount);

        uint256 expectedShares = vault.toShares(amount);
        uint256 expectedRewardShares = vault.toRewardShares(
            amount,
            MAX_LOCK_TIME
        );

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint256 shares = vault.deposit(bob, amount, MAX_LOCK_TIME);
        vm.stopPrank();

        (
            uint256 unlockTime,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(bob);
        uint256[] memory rewardIndices = vault.getUserIndices(bob);

        assertEq(
            unlockTime,
            block.timestamp + MAX_LOCK_TIME,
            "wrong unlock time"
        );

        assertEq(rewardIndices[0], vault.currIndices(0), "wrong reward index");
        assertEq(rewardIndices[1], vault.currIndices(1), "wrong reward index");

        assertEq(lockAmount, amount, "wrong lock amount");
        assertEq(lockRewardShares, expectedRewardShares, "wrong rewardShares");
        assertEq(shares, expectedShares, "wrong shares");
        assertEq(asset.balanceOf(alice), 0, "wrong asset bal");
        assertEq(
            asset.balanceOf(address(strategy)),
            amount,
            "wrong asset bal strat"
        );
        assertEq(
            strategy.balanceOf(address(vault)),
            amount * 1e9,
            "wrong strat bal in vault"
        );
    }

    function test_deposit_with_increased_share_price() public {
        uint256 amount = 1e18;
        _deposit(alice, amount, MAX_LOCK_TIME);

        deal(address(asset), address(alice), amount);
        vm.prank(alice);
        asset.transfer(address(strategy), amount);

        _deposit(bob, amount, MAX_LOCK_TIME);

        assertEq(vault.balanceOf(alice), amount, "wrong vault bal alice");
        assertEq(vault.balanceOf(bob), amount / 2, "wrong vault bal bob");
        assertEq(
            asset.balanceOf(address(strategy)),
            amount * 3,
            "wrong asset bal strat"
        );
    }

    function test_cannot_lock_for_more_than_max() public {
        deal(address(asset), alice, 1e18);
        vm.startPrank(alice);
        asset.approve(address(vault), 1e18);
        vm.expectRevert("LOCK_TIME");
        vault.deposit(alice, 1e18, MAX_LOCK_TIME + 1);
        vm.stopPrank();
    }

    function test_withdraw() public {
        _deposit(alice, 1e18, 365 days);

        vm.warp(block.timestamp + 365 days + 1);

        vm.prank(alice);
        vault.withdraw(alice, alice);

        (
            uint256 unlockTime,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(alice);

        assertEq(asset.balanceOf(alice), 1e18, "asset");
        assertEq(vault.balanceOf(alice), 0, "shares");
        assertEq(unlockTime, 0, "unlockTime");
        assertEq(lockAmount, 0, "lockAmount");
        assertEq(lockRewardShares, 0, "reward shares");
    }

    function test_withdraw_without_strategy() public {
        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = address(rewardToken1);
        _rewardTokens[1] = address(rewardToken2);

        vault = new LockVault();
        vault.initialize(
            address(asset),
            _rewardTokens,
            address(0),
            MAX_LOCK_TIME,
            "VaultName",
            "v"
        );


        _deposit(alice, 1e18, 365 days);

        vm.warp(block.timestamp + 365 days + 1);

        vm.prank(alice);
        vault.withdraw(alice, alice);

        (
            uint256 unlockTime,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(alice);

        assertEq(asset.balanceOf(alice), 1e18, "asset");
        assertEq(vault.balanceOf(alice), 0, "shares");
        assertEq(unlockTime, 0, "unlockTime");
        assertEq(lockAmount, 0, "lockAmount");
        assertEq(lockRewardShares, 0, "reward shares");
    }

    function test_withdraw_claims() public {
        _deposit(alice, 1e18, 365 days);

        vm.warp(block.timestamp + 365 days + 1);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18;

        _distribute(amounts);

        vm.prank(alice);
        vault.withdraw(alice, alice);

        (
            uint256 unlockTime,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(alice);
        uint256[] memory rewardIndices = vault.getUserIndices(alice);

        assertEq(asset.balanceOf(alice), 1e18, "asset");
        assertEq(vault.balanceOf(alice), 0, "shares");
        assertEq(unlockTime, 0, "unlockTime");
        assertEq(lockAmount, 0, "lockAmount");
        assertEq(lockRewardShares, 0, "reward shares");

        assertEq(rewardToken1.balanceOf(alice), 9.99e18, "reward");
        assertEq(rewardIndices.length, 0, "rewardIndices.length");
    }

    function test_only_authorized_can_withdraw() public {
        _deposit(alice, 1e18, 365 days);

        vm.warp(block.timestamp + 365 days + 1);

        vm.startPrank(bob);
        vm.expectRevert(); // Allowance underflow
        vault.withdraw(alice, bob);
        vm.stopPrank();

        vm.prank(alice);
        vault.approve(bob, 1e27);

        vm.prank(bob);
        vault.withdraw(alice, bob);

        assertEq(asset.balanceOf(bob), 1e18, "Bob didn't receive the funds");
    }

    function test_withdraw_with_increased_share_price() public {
        uint256 amount = 1e18;
        _deposit(alice, amount, MAX_LOCK_TIME);

        deal(address(asset), address(bob), amount);
        vm.prank(bob);
        asset.transfer(address(strategy), amount);

        vm.warp(block.timestamp + MAX_LOCK_TIME + 1);

        vm.prank(alice);
        vault.withdraw(alice, alice);

        // @dev for some reason solidity decided to have a 1 wei rounding issue here
        assertApproxEqAbs(
            vault.balanceOf(alice),
            0,
            1,
            "wrong vault bal alice"
        );
        assertApproxEqAbs(
            asset.balanceOf(alice),
            amount * 2,
            1,
            "wrong asset bal alice"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(strategy)),
            0,
            1,
            "wrong asset bal strat"
        );
    }

    function test_cannot_withdraw_twice() public {
        _deposit(alice, 1e18, 365 days);
        vm.warp(block.timestamp + 365 days + 1);

        vm.startPrank(alice);
        vault.withdraw(alice, alice);

        assertEq(
            asset.balanceOf(alice),
            1e18,
            "Alice didn't receive the funds"
        );

        vm.expectRevert("NO_LOCK");
        vault.withdraw(alice, alice);
    }

    /*//////////////////////////////////////////////////////////////
                            INCREASE LOCK AMOUNT
    //////////////////////////////////////////////////////////////*/

    function test_increase_amount(uint256 amount) public {
        vm.assume(amount > 1e9 && amount <= 100_000e18);

        uint256 initalDeposit = 1e18;
        deal(address(asset), alice, initalDeposit + amount);

        vm.startPrank(alice);
        asset.approve(address(vault), initalDeposit + amount);
        vault.deposit(alice, initalDeposit, MAX_LOCK_TIME);

        uint256 expectedShares = (initalDeposit) + vault.toShares(amount);
        uint256 expectedRewardShares = initalDeposit +
            vault.toRewardShares(amount, MAX_LOCK_TIME / 2);

        vm.warp(block.timestamp + 365 days * 2);
        vault.increaseLockAmount(alice, amount);
        vm.stopPrank();

        (, uint256 lockAmount, uint256 lockRewardShares) = vault.locks(alice);
        assertEq(initalDeposit + amount, lockAmount, "wrong lock amount");
        assertEq(expectedRewardShares, lockRewardShares, "wrong reward shares");
        assertEq(expectedShares, vault.balanceOf(alice), "wrong shares");
    }

    function test_increase_lock_amount_for() public {
        uint256 amount = 1e18;
        _deposit(alice, amount, 365 days);

        deal(address(asset), bob, amount);

        vm.startPrank(bob);
        asset.approve(address(vault), amount);
        vault.increaseLockAmount(alice, amount);
        vm.stopPrank();

        (, uint256 lockAmount, ) = vault.locks(alice);
        assertEq(lockAmount, amount * 2, "lock amount didn't change");
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS
    //////////////////////////////////////////////////////////////*/

    function test_distribute_rewards(uint256 amount) public {
        vm.assume(amount > 10e18 && amount < 100_000_000_000e18);

        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;

        deal(address(rewardToken1), address(this), amount);
        rewardToken1.approve(address(vault), amount);
        vault.distributeRewards(amounts);

        vault.accrueUser(alice);
        vault.accrueUser(bob);

        uint256 amountAfterFees = amount -
            ((amount * vault.PROTOCOL_FEE()) / 10_000);

        assertEq(
            vault.accruedRewards(alice, 0),
            (amountAfterFees * 4) / 5,
            "Alice got wrong reward amount"
        );
        assertEq(
            vault.accruedRewards(bob, 0),
            amountAfterFees / 5,
            "Bob got wrong reward amount"
        );
    }

    function test_distribute_multiple_rewards(uint256 amount) public {
        vm.assume(amount > 10e18 && amount < 100_000_000_000e18);

        uint256 amount2 = amount / 2;

        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount2;

        deal(address(rewardToken1), address(this), amount);
        rewardToken1.approve(address(vault), amount);

        deal(address(rewardToken2), address(this), amount2);
        rewardToken2.approve(address(vault), amount2);

        vault.distributeRewards(amounts);

        vault.accrueUser(alice);
        vault.accrueUser(bob);

        uint256 amountAfterFees = amount -
            ((amount * vault.PROTOCOL_FEE()) / 10_000);
        uint256 amountAfterFees2 = amount2 -
            ((amount2 * vault.PROTOCOL_FEE()) / 10_000);

        assertEq(
            vault.accruedRewards(alice, 0),
            (amountAfterFees * 4) / 5,
            "Alice got wrong reward amount"
        );
        assertEq(
            vault.accruedRewards(alice, 1),
            (amountAfterFees2 * 4) / 5,
            "Alice got wrong reward amount2"
        );

        assertEq(
            vault.accruedRewards(bob, 0),
            amountAfterFees / 5,
            "Bob got wrong reward amount"
        );
        assertEq(
            vault.accruedRewards(bob, 1),
            amountAfterFees2 / 5,
            "Bob got wrong reward amount2"
        );
    }

    function test_lock_changes_affect_distribution() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);

        uint256 amount = 100e18;
        uint256 amountAfterFees = amount -
            (amount * vault.PROTOCOL_FEE()) /
            10_000;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;

        _distribute(amounts);

        deal(address(asset), bob, 1e18);
        vm.startPrank(bob);
        asset.approve(address(vault), 1e18);
        vault.increaseLockAmount(bob, 1e18);
        vm.stopPrank();

        assertEq(
            vault.accruedRewards(bob, 0),
            amountAfterFees / 5,
            "Bob got wrong reward amount 1"
        );

        _distribute(amounts);

        vault.accrueUser(alice);
        vault.accrueUser(bob);

        uint256 aliceExpectedRewards = (amountAfterFees * 4) /
            5 +
            (amountAfterFees * 4) /
            6;
        uint256 bobExpectedRewards = amountAfterFees /
            5 +
            (amountAfterFees * 2) /
            6;

        assertEq(
            vault.accruedRewards(alice, 0),
            aliceExpectedRewards,
            "Alice got wrong reward amount"
        );
        assertEq(
            vault.accruedRewards(bob, 0),
            bobExpectedRewards,
            "Bob got wrong reward amount 2"
        );
    }

    function test_accrue_before_amount_increase() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;

        _distribute(amounts);

        deal(address(asset), alice, 1e18);
        vm.startPrank(alice);
        asset.approve(address(vault), 1e18);
        vault.increaseLockAmount(alice, 1e18);
        vm.stopPrank();

        uint256 amountAfterFees = 100e18 -
            (100e18 * vault.PROTOCOL_FEE()) /
            10_000;

        // with the initial balances, alice should receive half of the total reward amount.
        // The increase in her lock amount shouldn't have an affect here.
        assertEq(
            vault.accruedRewards(alice, 0),
            amountAfterFees / 2,
            "Alice got wrong reward amount"
        );
    }

    function test_claim() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 0;

        _distribute(amounts);

        vault.claim(alice);

        uint256 amountAfterFees = 100e18 -
            (100e18 * vault.PROTOCOL_FEE()) /
            10_000;

        assertEq(
            rewardToken1.balanceOf(alice),
            amountAfterFees,
            "didn't claim rewards"
        );
    }

    function test_claim_multiple_rewards() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 10e18;

        _distribute(amounts);

        vault.claim(alice);

        uint256 amountAfterFees = 100e18 -
            (100e18 * vault.PROTOCOL_FEE()) /
            10_000;
        uint256 amountAfterFees2 = 10e18 -
            (10e18 * vault.PROTOCOL_FEE()) /
            10_000;

        assertEq(
            rewardToken1.balanceOf(alice),
            amountAfterFees,
            "didn't claim rewards"
        );
        assertEq(
            rewardToken2.balanceOf(alice),
            amountAfterFees2,
            "didn't claim rewards2"
        );
    }

    function test_claim_doesnt_break_withdraw_nor_deposit() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100e18;
        amounts[1] = 0;

        _distribute(amounts);

        vault.claim(alice);

        vm.warp(block.timestamp + MAX_LOCK_TIME + 1);

        vm.prank(alice);
        vault.withdraw(alice, alice);

        assertEq(
            asset.balanceOf(alice),
            1e18,
            "Alice didn't receive the funds"
        );

        _deposit(alice, 1e18, MAX_LOCK_TIME);
    }

    /*//////////////////////////////////////////////////////////////
                                TRANSFER
    //////////////////////////////////////////////////////////////*/

    function testFail_transfer() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);

        vm.prank(alice);
        vault.transfer(bob, 1e18);
    }

    function testFail_transferFrom() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);

        vm.prank(alice);
        vault.approve(bob, 1e18);

        vm.prank(bob);
        vault.transferFrom(alice, bob, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address user, uint256 amount, uint256 lockTime) internal {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(user, amount, lockTime);
        vm.stopPrank();
    }

    function _distribute(uint256[] memory amounts) internal {
        for (uint256 i; i < amounts.length; i++) {
            deal(address(rewardTokens[i]), address(this), amounts[i]);
            rewardTokens[i].approve(address(vault), amounts[i]);
        }
        vault.distributeRewards(amounts);
    }
}
