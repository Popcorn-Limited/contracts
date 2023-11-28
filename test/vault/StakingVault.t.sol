pragma solidity ^0.8.0;
import "forge-std/Test.sol";

import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {MockERC4626} from "../utils/mocks/MockERC4626.sol";
import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

import {StakingVault} from "../../src/vaults/StakingVault.sol";

contract StakingVaultTest is Test {
    StakingVault vault;

    MockERC20 asset = new MockERC20("A", "Asset", 18);
    MockERC20 rewardToken = new MockERC20("R", "Reward", 18);
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
        vault = new StakingVault(
            address(asset),
            MAX_LOCK_TIME,
            address(rewardToken),
            address(strategy),
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
            uint128 lockTime,
            uint128 unlockTime,
            uint256 rewardIndex,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(alice);

        assertEq(
            unlockTime,
            block.timestamp + MAX_LOCK_TIME,
            "wrong unlock time"
        );
        assertEq(rewardIndex, vault.currIndex(), "wrong reward index");
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
            uint128 lockTime,
            uint128 unlockTime,
            uint256 rewardIndex,
            uint256 lockAmount,
            uint256 lockRewardShares
        ) = vault.locks(bob);

        assertEq(
            unlockTime,
            block.timestamp + MAX_LOCK_TIME,
            "wrong unlock time"
        );
        assertEq(rewardIndex, vault.currIndex(), "wrong reward index");
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

        (, , , uint256 lockAmount, uint256 lockRewardShares) = vault.locks(
            alice
        );
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

        (, , , uint256 deposit, ) = vault.locks(alice);
        assertEq(deposit, amount * 2, "lock amount didn't change");
    }

    /*//////////////////////////////////////////////////////////////
                            INCREASE LOCK TIME
    //////////////////////////////////////////////////////////////*/

    function test_increase_lock_time(uint256 newUnlockTime) public {
        // initial lock time is 1 day. `increaseLockTime()` forces you to increase
        // the lock time so limit the min value as well
        vm.assume(newUnlockTime > 2 days && newUnlockTime <= MAX_LOCK_TIME);

        deal(address(asset), alice, 1e18);

        vm.startPrank(alice);
        asset.approve(address(vault), 1e18);
        vault.deposit(alice, 1e18, 1 days);
        vault.increaseLockTime(newUnlockTime);
        vm.stopPrank();

        uint256 expectedShares = (1e18 * newUnlockTime) / MAX_LOCK_TIME;
        (uint128 lockTime, uint128 unlockTime, , , uint256 lockShares) = vault
            .locks(alice);
        assertEq(
            unlockTime,
            block.timestamp + newUnlockTime,
            "wrong unlock time"
        );
        assertEq(lockShares, expectedShares, "wrong shares");
    }

    function test_cannot_increase_lock_for_more_than_max() public {
        vm.expectRevert("LOCK_TIME");
        _deposit(alice, 1e18, 365 days);

        vm.startPrank(alice);
        vm.expectRevert("LOCK_TIME");
        vault.increaseLockTime(MAX_LOCK_TIME + 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS
    //////////////////////////////////////////////////////////////*/

    function test_distribute_rewards(uint256 amount) public {
        vm.assume(amount > 10e18 && amount < 100_000_000_000e18);

        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);

        deal(address(rewardToken), address(this), amount);
        rewardToken.approve(address(vault), amount);
        vault.distributeRewards(amount);

        vault.accrueUser(alice);
        vault.accrueUser(bob);

        uint256 amountAfterFees = amount -
            ((amount * vault.PROTOCOL_FEE()) / 10_000);

        assertEq(
            vault.accruedRewards(alice),
            (amountAfterFees * 4) / 5,
            "Alice got wrong reward amount"
        );
        assertEq(
            vault.accruedRewards(bob),
            amountAfterFees / 5,
            "Bob got wrong reward amount"
        );
    }

    function test_lock_changes_affect_distribution() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME / 4);

        uint256 amount = 100e18;
        uint256 amountAfterFees = amount -
            (amount * vault.PROTOCOL_FEE()) /
            10_000;

        _distribute(amount);

        vm.prank(bob);
        vault.increaseLockTime(MAX_LOCK_TIME / 2);

        assertEq(
            vault.accruedRewards(bob),
            amountAfterFees / 5,
            "Bob got wrong reward amount"
        );

        _distribute(amount);

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
            vault.accruedRewards(alice),
            aliceExpectedRewards,
            "Alice got wrong reward amount"
        );
        assertEq(
            vault.accruedRewards(bob),
            bobExpectedRewards,
            "Bob got wrong reward amount"
        );
    }

    function test_accrue_before_amount_increase() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _deposit(bob, 1e18, MAX_LOCK_TIME);
        _distribute(100e18);

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
            vault.accruedRewards(alice),
            amountAfterFees / 2,
            "Alice got wrong reward amount"
        );
    }

    function test_accrue_before_lock_time_increase() public {
        _deposit(alice, 1e18, 365 days);
        _deposit(bob, 1e18, 365 days);
        _distribute(100e18);

        vm.startPrank(alice);
        vault.increaseLockTime(365 days * 2);
        vm.stopPrank();

        uint256 amountAfterFees = 100e18 -
            (100e18 * vault.PROTOCOL_FEE()) /
            10_000;
        // with the initial lock times, alice should receive half of the total reward amount (100e18)
        assertEq(
            vault.accruedRewards(alice),
            amountAfterFees / 2,
            "Alice got wrong reward amount"
        );
    }

    function test_claim() public {
        _deposit(alice, 1e18, MAX_LOCK_TIME);
        _distribute(100e18);

        vault.accrueUser(alice);
        vault.claim(alice);

        uint256 amountAfterFees = 100e18 -
            (100e18 * vault.PROTOCOL_FEE()) /
            10_000;

        assertEq(
            rewardToken.balanceOf(alice),
            amountAfterFees,
            "didn't claim rewards"
        );
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

    function _distribute(uint256 amount) internal {
        deal(address(rewardToken), address(this), amount);
        rewardToken.approve(address(vault), amount);
        vault.distributeRewards(amount);
    }
}
