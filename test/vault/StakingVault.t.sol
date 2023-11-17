pragma solidity ^0.8.0;
import "forge-std/Test.sol";

import {MockERC20} from "../utils/mocks/MockERC20.sol";

import {StakingVault} from "../../src/vaults/StakingVault.sol";

contract StakingVaultTest is Test {
    StakingVault vault;

    MockERC20 asset = new MockERC20("A", "Asset", 18);
    MockERC20 rewardToken = new MockERC20("R", "Reward", 18);

    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint MAX_LOCK_TIME = 365 days * 4;

    function setUp() public {
        vault = new StakingVault(address(asset), MAX_LOCK_TIME, address(rewardToken));
    }

    function test_deposit(uint amount) public {
        vm.assume(amount != 0 && amount <= 100_000e18);
        deal(address(asset), alice, amount);

        vm.startPrank(alice);
        asset.approve(address(vault), amount);
        uint shares = vault.deposit(amount, 365 days * 4);
        vm.stopPrank();

        (uint unlockTime, uint rewardIndex, uint lockAmount, uint lockShares) = vault.locks(alice);

        assertEq(unlockTime, block.timestamp + 365 days * 4, "wrong unlock time");
        assertEq(rewardIndex, vault.currIndex(), "wrong reward index");
        assertEq(lockAmount, amount, "wrong lock amount");
        assertEq(shares, lockShares, "wrong shares");
        assertEq(amount, lockShares, "wrong shares");
    }

    function test_increase_lock_time(uint newUnlockTime) public {
        // initial lock time is 1 day. `increaseLockTime()` forces you to increase
        // the lock time so limit the min value as well
        vm.assume(newUnlockTime > 2 days && newUnlockTime <= MAX_LOCK_TIME);

        deal(address(asset), alice, 1e18);

        vm.startPrank(alice);
        asset.approve(address(vault), 1e18);
        vault.deposit(1e18, 1 days);
        vault.increaseLockTime(newUnlockTime);
        vm.stopPrank();

        uint expectedShares = 1e18 * newUnlockTime / MAX_LOCK_TIME;
        (uint unlockTime, ,, uint lockShares) = vault.locks(alice);
        assertEq(unlockTime, block.timestamp + newUnlockTime, "wrong unlock time");
        assertEq(lockShares, expectedShares, "wrong shares");
    }

    function test_increase_amount(uint amount) public {
        vm.assume(amount > 0 && amount <= 100_000e18);

        // 1e18 is the initial deposit amount
        deal(address(asset), alice, 1e18 + amount);

        vm.startPrank(alice);
        asset.approve(address(vault), 1e18 + amount);
        vault.deposit(1e18, MAX_LOCK_TIME);
        vault.increaseLockAmount(amount);
        vm.stopPrank();
    
        (,,uint lockAmount, uint lockShares) = vault.locks(alice);

        uint expectedShares = vault.toShares(1e18 + amount, MAX_LOCK_TIME);
        assertEq(1e18 + amount, lockAmount, "wrong lock amount");
        assertEq(expectedShares, lockShares, "wrong shares");
    }

    function test_distribute_rewards(uint amount) public {
        vm.assume(amount > 10e18 && amount < 100_000_000_000e18);
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);
    
        deal(address(rewardToken), address(this), amount);
        rewardToken.approve(address(vault), amount);
        vault.distributeRewards(amount);

        vault.accrueUser(alice);
        vault.accrueUser(bob);

        uint amountAfterFees = amount - amount * vault.PROTOCOL_FEE() / 10_000;
        assertEq(vault.accruedRewards(alice), amountAfterFees * 4 / 5, "Alice got wrong reward amount");
        assertEq(vault.accruedRewards(bob), amountAfterFees / 5, "Bob got wrong reward amount");
    }

    function test_lock_changes_affect_distribution() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);

        uint amount = 100e18;
        uint amountAfterFees = amount - amount * vault.PROTOCOL_FEE() / 10_000;

        _distribute(amount);

        vm.prank(bob);
        vault.increaseLockTime(MAX_LOCK_TIME / 2);

        assertEq(vault.accruedRewards(bob), amountAfterFees / 5, "Bob got wrong reward amount");

        _distribute(amount);

        vault.accrueUser(alice);
        vault.accrueUser(bob);

        uint aliceExpectedRewards = amountAfterFees * 4 / 5 + amountAfterFees * 4 / 6;
        uint bobExpectedRewards = amountAfterFees / 5 + amountAfterFees * 2 / 6;

        assertEq(vault.accruedRewards(alice), aliceExpectedRewards, "Alice got wrong reward amount");
        assertEq(vault.accruedRewards(bob), bobExpectedRewards, "Bob got wrong reward amount");
    }

    function test_claim() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _distribute(100e18);

        vault.accrueUser(alice);
        vault.claim(alice);

        uint amountAfterFees = 100e18 - 100e18 * vault.PROTOCOL_FEE() / 10_000;

        assertEq(rewardToken.balanceOf(alice), amountAfterFees, "didn't claim rewards");
    }


    function test_accrue_before_amount_increase() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME);
        _distribute(100e18);

        deal(address(asset), alice, 1e18);
        vm.startPrank(alice);
        asset.approve(address(vault), 1e18);
        vault.increaseLockAmount(1e18);
        vm.stopPrank();

        uint amountAfterFees = 100e18 - 100e18 * vault.PROTOCOL_FEE() / 10_000;
        // with the initial balances, alice should receive half of the total reward amount.
        // The increase in her lock amount shouldn't have an affect here.
        assertEq(vault.accruedRewards(alice), amountAfterFees / 2, "Alice got wrong reward amount");
    }

    function test_accrue_before_lock_time_increase() public {
        _deposit(alice, 1e18, 365 days);
        _deposit(bob, 1e18, 365 days);
        _distribute(100e18);

        vm.startPrank(alice);
        vault.increaseLockTime(365 days * 2);
        vm.stopPrank();

        uint amountAfterFees = 100e18 - 100e18 * vault.PROTOCOL_FEE() / 10_000;
        // with the initial lock times, alice should receive half of the total reward amount (100e18)
        assertEq(vault.accruedRewards(alice), amountAfterFees / 2, "Alice got wrong reward amount");
    }

    function test_cannot_lock_for_more_than_max() public {
        deal(address(asset), alice, 1e18);
        vm.startPrank(alice);
        asset.approve(address(vault), 1e18);
        vm.expectRevert("LOCK_TIME");
        vault.deposit(1e18, MAX_LOCK_TIME + 1);
        vm.stopPrank();
    }

    function test_cannot_increase_lock_for_more_than_max() public {
        vm.expectRevert("LOCK_TIME");
        _deposit(alice, 1e18, 365 days);
        vm.startPrank(alice);
        vm.expectRevert("LOCK_TIME");
        vault.increaseLockTime(MAX_LOCK_TIME + 1);
        vm.stopPrank();
    }

    //
    // HELPER FUNCTIONS
    //

    function _deposit(address user, uint amount, uint lockTime) internal {
        deal(address(asset), user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, lockTime);
        vm.stopPrank();
    }

    function _distribute(uint amount) internal {
        deal(address(rewardToken), address(this), amount);
        rewardToken.approve(address(vault), amount);
        vault.distributeRewards(amount);
    }
}