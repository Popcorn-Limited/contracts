// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";
import { MockERC20 } from "./utils/mocks/MockERC20.sol";
import { IMultiRewardEscrow } from "../src/interfaces/IMultiRewardEscrow.sol";
import { MultiRewardStaking, IERC20 } from "../src/utils/MultiRewardStaking.sol";
import { MultiRewardEscrow } from "../src/utils/MultiRewardEscrow.sol";

contract MultiRewardStakingTest is Test {
  using SafeCastLib for uint256;

  MockERC20 stakingToken;
  MockERC20 rewardToken1;
  MockERC20 rewardToken2;
  IERC20 iRewardToken1;
  IERC20 iRewardToken2;
  MultiRewardStaking staking;
  MultiRewardEscrow escrow;

  address alice = address(0xABCD);
  address bob = address(0xDCBA);
  address feeRecipient = address(0x9999);

  bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  event RewardInfoUpdate(IERC20 rewardsToken, uint160 rewardsPerSecond, uint32 rewardsEndTimestamp);
  event RewardsClaimed(address indexed user, IERC20 rewardsToken, uint256 amount, bool escrowed);

  function setUp() public {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    stakingToken = new MockERC20("Staking Token", "STKN", 18);

    rewardToken1 = new MockERC20("RewardsToken1", "RTKN1", 18);
    rewardToken2 = new MockERC20("RewardsToken2", "RTKN2", 18);
    iRewardToken1 = IERC20(address(rewardToken1));
    iRewardToken2 = IERC20(address(rewardToken2));

    escrow = new MultiRewardEscrow(address(this), feeRecipient);

    staking = new MultiRewardStaking();
    staking.initialize(IERC20(address(stakingToken)), IMultiRewardEscrow(address(escrow)), address(this));
  }

  /*//////////////////////////////////////////////////////////////
                            VIEW LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__metaData() public {
    assertEq(staking.name(), "Staked Staking Token");
    assertEq(staking.symbol(), "pst-STKN");
    assertEq(staking.decimals(), stakingToken.decimals());

    MockERC20 newStakingToken = new MockERC20("New Staking Token", "NSTKN", 6);

    MultiRewardStaking newStaking = new MultiRewardStaking();
    newStaking.initialize(IERC20(address(newStakingToken)), IMultiRewardEscrow(address(escrow)), address(this));

    assertEq(newStaking.name(), "Staked New Staking Token");
    assertEq(newStaking.symbol(), "pst-NSTKN");
    assertEq(newStaking.decimals(), newStakingToken.decimals());
  }

  function test__getAllRewardsTokens() public {
    _addRewardToken(rewardToken1);
    IERC20[] memory rewardTokens = staking.getAllRewardsTokens();

    assertEq(rewardTokens.length, 1);
    assertEq(address(rewardTokens[0]), address(rewardToken1));
  }

  /*//////////////////////////////////////////////////////////////
                         DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__single_deposit_withdraw(uint128 amount) public {
    if (amount == 0) amount = 1;

    uint256 aliceUnderlyingAmount = amount;

    stakingToken.mint(alice, aliceUnderlyingAmount);

    vm.prank(alice);
    stakingToken.approve(address(staking), aliceUnderlyingAmount);
    assertEq(stakingToken.allowance(alice, address(staking)), aliceUnderlyingAmount);

    uint256 alicePreDepositBal = stakingToken.balanceOf(alice);

    vm.prank(alice);
    uint256 aliceShareAmount = staking.deposit(aliceUnderlyingAmount, alice);

    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(aliceUnderlyingAmount, aliceShareAmount);
    assertEq(staking.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    assertEq(staking.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    assertEq(staking.totalSupply(), aliceShareAmount);
    assertEq(staking.totalAssets(), aliceUnderlyingAmount);
    assertEq(staking.balanceOf(alice), aliceShareAmount);
    assertEq(staking.convertToAssets(staking.balanceOf(alice)), aliceUnderlyingAmount);
    assertEq(stakingToken.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

    vm.prank(alice);
    staking.withdraw(aliceUnderlyingAmount, alice, alice);

    assertEq(staking.totalAssets(), 0);
    assertEq(staking.balanceOf(alice), 0);
    assertEq(staking.convertToAssets(staking.balanceOf(alice)), 0);
    assertEq(stakingToken.balanceOf(alice), alicePreDepositBal);
  }

  function test__deposit_zero() public {
    staking.deposit(0, address(this));
    assertEq(staking.balanceOf(address(this)), 0);
  }

  function test__withdraw_zero() public {
    staking.withdraw(0, address(this), address(this));
  }

  function testFail__deposit_with_no_approval() public {
    staking.deposit(1e18, address(this));
  }

  function testFail__deposit_with_not_enough_approval() public {
    stakingToken.mint(address(this), 0.5e18);
    stakingToken.approve(address(staking), 0.5e18);
    assertEq(stakingToken.allowance(address(this), address(staking)), 0.5e18);

    staking.deposit(1e18, address(this));
  }

  function testFail__withdraw_with_not_enough_underlying_amount() public {
    stakingToken.mint(address(this), 0.5e18);
    stakingToken.approve(address(staking), 0.5e18);

    staking.deposit(0.5e18, address(this));

    staking.withdraw(1e18, address(this), address(this));
  }

  function testFail__withdraw_with_no_underlying_amount() public {
    staking.withdraw(1e18, address(this), address(this));
  }

  /*//////////////////////////////////////////////////////////////
                         MINT/REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__single_mint_redeem(uint128 amount) public {
    if (amount == 0) amount = 1;

    uint256 aliceShareAmount = amount;

    stakingToken.mint(alice, aliceShareAmount);

    vm.prank(alice);
    stakingToken.approve(address(staking), aliceShareAmount);
    assertEq(stakingToken.allowance(alice, address(staking)), aliceShareAmount);

    uint256 alicePreDepositBal = stakingToken.balanceOf(alice);

    vm.prank(alice);
    uint256 aliceUnderlyingAmount = staking.mint(aliceShareAmount, alice);

    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(aliceShareAmount, aliceUnderlyingAmount);
    assertEq(staking.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    assertEq(staking.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    assertEq(staking.totalSupply(), aliceShareAmount);
    assertEq(staking.totalAssets(), aliceUnderlyingAmount);
    assertEq(staking.balanceOf(alice), aliceUnderlyingAmount);
    assertEq(staking.convertToAssets(staking.balanceOf(alice)), aliceUnderlyingAmount);
    assertEq(stakingToken.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

    vm.prank(alice);
    staking.redeem(aliceShareAmount, alice, alice);

    assertEq(staking.totalAssets(), 0);
    assertEq(staking.balanceOf(alice), 0);
    assertEq(staking.convertToAssets(staking.balanceOf(alice)), 0);
    assertEq(stakingToken.balanceOf(alice), alicePreDepositBal);
  }

  function test__mint_zero() public {
    staking.mint(0, address(this));
    assertEq(staking.balanceOf(address(this)), 0);
  }

  function test__redeem_zero() public {
    staking.redeem(0, address(this), address(this));
  }

  function testFail__mint_with_no_approval() public {
    staking.mint(1e18, address(this));
  }

  function testFail__redeem_with_not_enough_share_amount() public {
    stakingToken.mint(address(this), 0.5e18);
    stakingToken.approve(address(staking), 0.5e18);

    staking.deposit(0.5e18, address(this));

    staking.redeem(1e18, address(this), address(this));
  }

  function testFail__redeem_with_no_share_amount() public {
    staking.redeem(1e18, address(this), address(this));
  }

  /*//////////////////////////////////////////////////////////////
                            PERMIT LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__permit() public {
    uint256 privateKey = 0xBEEF;
    address owner = vm.addr(privateKey);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      privateKey,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          staking.DOMAIN_SEPARATOR(),
          keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
        )
      )
    );

    staking.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

    assertEq(staking.allowance(owner, address(0xCAFE)), 1e18);
    assertEq(staking.nonces(owner), 1);
  }

  /*//////////////////////////////////////////////////////////////
                          ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__accrual() public {
    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 5 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 5 ether);
    staking.deposit(1 ether);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    uint256 callTimestamp = block.timestamp;
    staking.deposit(1 ether);

    (, , , uint224 index, uint32 lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 2 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    // Should be 1 ether of rewards
    assertEq(staking.accruedRewards(alice, iRewardToken1), 1 ether);

    // 20% of rewards paid out
    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    staking.mint(2 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 2.5 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 2 ether);

    // 90% of rewards paid out
    vm.warp(block.timestamp + 70);

    callTimestamp = block.timestamp;
    staking.withdraw(2 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 4.25 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 9 ether);

    // 100% of rewards paid out
    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    staking.redeem(1 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 4.75 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 10 ether);
  }

  function test__accrual_multiple_rewardsToken() public {
    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 5 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 5 ether);
    staking.deposit(1 ether);

    vm.warp(block.timestamp + 10);

    uint256 callTimestamp = block.timestamp;
    staking.deposit(1 ether);

    // RewardsToken 1 -- 10% accrued
    (, , , uint224 indexReward1, uint32 lastUpdatedTimestampReward1) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(indexReward1), 2 ether);
    assertEq(uint256(lastUpdatedTimestampReward1), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), indexReward1);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 1 ether);

    // Add new rewardsToken
    vm.stopPrank();
    _addRewardToken(rewardToken2);
    vm.startPrank(alice);

    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    staking.deposit(2 ether);

    // RewardsToken 1 -- 20% accrued
    (, , , indexReward1, lastUpdatedTimestampReward1) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(indexReward1), 2.5 ether);
    assertEq(uint256(lastUpdatedTimestampReward1), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), indexReward1);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 2 ether);

    // RewardsToken 2 -- 10% accrued
    (, , , uint224 indexReward2, uint32 lastUpdatedTimestampReward2) = staking.rewardInfos(iRewardToken2);
    assertEq(uint256(indexReward2), 1.5 ether);
    assertEq(uint256(lastUpdatedTimestampReward2), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken2), indexReward2);
    assertEq(staking.accruedRewards(alice, iRewardToken2), 1 ether);

    vm.warp(block.timestamp + 80);

    callTimestamp = block.timestamp;
    staking.deposit(1 ether);

    // RewardsToken 1 -- 100% accrued
    (, , , indexReward1, lastUpdatedTimestampReward1) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(indexReward1), 4.5 ether);
    assertEq(uint256(lastUpdatedTimestampReward1), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), indexReward1);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 10 ether);

    // RewardsToken 2 -- 90% accrued
    (, , , indexReward2, lastUpdatedTimestampReward2) = staking.rewardInfos(iRewardToken2);
    assertEq(uint256(indexReward2), 3.5 ether);
    assertEq(uint256(lastUpdatedTimestampReward2), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken2), indexReward2);
    assertEq(staking.accruedRewards(alice, iRewardToken2), 9 ether);
  }

  function test__accrual_on_claim() public {
    // Prepare array for `claimRewards`
    IERC20[] memory rewardsTokenKeys = new IERC20[](1);
    rewardsTokenKeys[0] = iRewardToken1;

    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 5 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 5 ether);
    staking.deposit(1 ether);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    uint256 callTimestamp = block.timestamp;
    staking.claimRewards(alice, rewardsTokenKeys);

    (, , , uint224 index, uint32 lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 2 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
  }

  function test__accrual_on_transfer() public {
    // Prepare array for `claimRewards`
    IERC20[] memory rewardsTokenKeys = new IERC20[](1);
    rewardsTokenKeys[0] = iRewardToken1;

    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 1 ether);
    stakingToken.mint(bob, 1 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 1 ether);
    staking.approve(bob, 1 ether);
    staking.deposit(1 ether);
    vm.stopPrank();

    vm.startPrank(bob);
    stakingToken.approve(address(staking), 1 ether);
    staking.approve(alice, 1 ether);
    staking.deposit(1 ether);
    vm.stopPrank();

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    uint256 callTimestamp = block.timestamp;
    vm.prank(alice);
    staking.transfer(bob, 1 ether);

    (, , , uint224 index, uint32 lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 1.5 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 0.5 ether);

    assertEq(staking.userIndex(bob, iRewardToken1), index);
    assertEq(staking.accruedRewards(bob, iRewardToken1), 0.5 ether);

    // 20% of rewards paid out
    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    vm.prank(alice);
    staking.transferFrom(bob, alice, 1 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 2 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    // Alice didnt accumulate more rewards since she didnt have any balance
    assertEq(staking.accruedRewards(alice, iRewardToken1), 0.5 ether);

    assertEq(staking.userIndex(bob, iRewardToken1), index);
    // Bob accrued the entire rewards
    assertEq(staking.accruedRewards(bob, iRewardToken1), 1.5 ether);

    // 30% of rewards paid out
    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    vm.prank(bob);
    staking.transferFrom(alice, address(this), 1 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 2.5 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 1 ether);

    // Bob didnt update his index since he is neither sender nor receiver of the token
    assertEq(staking.userIndex(bob, iRewardToken1), 2 ether);
    // Bob didnt accumulate since he is neither sender nor receiver of the token
    assertEq(staking.accruedRewards(bob, iRewardToken1), 1.5 ether);

    // This is synced to the current index
    assertEq(staking.userIndex(address(this), iRewardToken1), index);
    // This didnt accumulate since we didnt have any token before the transfer
    assertEq(staking.accruedRewards(address(this), iRewardToken1), 0 ether);

    // Alice claims 0.5 ether worth of rewards
    vm.prank(alice);
    staking.claimRewards(alice, rewardsTokenKeys);

    assertEq(staking.accruedRewards(alice, iRewardToken1), 0 ether);
    assertEq(rewardToken1.balanceOf(alice), 1 ether);
  }

  function test__no_accrual_after_end() public {
    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 2 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 2 ether);
    staking.deposit(1 ether);
    vm.stopPrank();

    // 100% of rewards paid out
    vm.warp(block.timestamp + 100);

    uint256 callTimestamp = block.timestamp;
    vm.prank(alice);
    staking.deposit(1 ether);

    (, , , uint224 index, uint32 lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 11 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 10 ether);

    // no more rewards after end time
    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    vm.prank(alice);
    staking.withdraw(1 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 11 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    // Alice didnt accumulate more rewards since we are past the end of the rewards
    assertEq(staking.accruedRewards(alice, iRewardToken1), 10 ether);
  }

  function test__accrual_with_user_joining_later() public {
    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 5 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 5 ether);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    uint256 callTimestamp = block.timestamp;
    staking.deposit(1 ether);

    (, , , uint224 index, uint32 lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    // Accrual doesnt start until someone deposits -- TODO does this change some of the rewardsEnd and rewardsSpeed assumptions?
    assertEq(uint256(index), 1 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 0);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    callTimestamp = block.timestamp;
    staking.mint(2 ether, bob);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 2 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 1 ether);

    assertEq(staking.userIndex(bob, iRewardToken1), index);
    assertEq(staking.accruedRewards(bob, iRewardToken1), 0);

    // 80% of rewards paid out
    vm.warp(block.timestamp + 70);

    staking.withdraw(0.5 ether);
    vm.stopPrank();
    vm.prank(bob);
    callTimestamp = block.timestamp;
    staking.withdraw(0.5 ether);

    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 4333333333333333333);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 3333333333333333333);

    assertEq(staking.userIndex(bob, iRewardToken1), index);
    assertEq(staking.accruedRewards(bob, iRewardToken1), 4666666666666666666);
    // Both accruals add up to 80% of rewards paid out
  }

  /*//////////////////////////////////////////////////////////////
                        ADD REWARDS TOKEN LOGIC
    //////////////////////////////////////////////////////////////*/

  function _addRewardToken(MockERC20 rewardsToken) internal {
    rewardsToken.mint(address(this), 10 ether);
    rewardsToken.approve(address(staking), 10 ether);

    staking.addRewardToken(IERC20(address(rewardsToken)), 0.1 ether, 10 ether, false, 0, 0, 0);
  }

  function _addRewardTokenWithZeroRewardsSpeed(MockERC20 rewardsToken) internal {
    staking.addRewardToken(IERC20(address(rewardsToken)), 0, 0, false, 0, 0, 0);
  }

  function _addRewardTokenWithEscrow(MockERC20 rewardsToken) internal {
    rewardsToken.mint(address(this), 10 ether);
    rewardsToken.approve(address(staking), 10 ether);

    staking.addRewardToken(IERC20(address(rewardsToken)), 0.1 ether, 10 ether, true, 1e17, 100, 0);
  }

  function test__addRewardToken() public {
    // Prepare to transfer reward tokens
    rewardToken1.mint(address(this), 10 ether);
    rewardToken1.approve(address(staking), 10 ether);

    uint256 callTimestamp = block.timestamp;
    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardInfoUpdate(iRewardToken1, 0.1 ether, (callTimestamp + 100).safeCastTo32());

    staking.addRewardToken(iRewardToken1, 0.1 ether, 10 ether, true, 10000000, 100, 20);

    // Confirm that all data is set correctly
    IERC20[] memory rewardTokens = staking.getAllRewardsTokens();
    assertEq(rewardTokens.length, 1);
    assertEq(address(rewardTokens[0]), address(iRewardToken1));

    (uint192 escrowPercentage, uint32 escrowDuration, uint32 offset) = staking.escrowInfos(iRewardToken1);
    assertEq(uint256(escrowDuration), 100);
    assertEq(uint256(escrowPercentage), 10000000);
    assertEq(uint256(offset), 20);

    (
      uint64 ONE,
      uint160 rewardsPerSecond,
      uint32 rewardsEndTimestamp,
      uint224 index,
      uint32 lastUpdatedTimestamp
    ) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(ONE), 1 ether);
    assertEq(rewardsPerSecond, 0.1 ether);
    assertEq(uint256(rewardsEndTimestamp), callTimestamp + 100);
    assertEq(index, 1 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);

    // Confirm token transfer
    assertEq(rewardToken1.balanceOf(address(this)), 0);
    assertEq(rewardToken1.balanceOf(address(staking)), 10 ether);
  }

  function test__addRewardToken_0_rewardsSpeed() public {
    uint256 callTimestamp = block.timestamp;
    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardInfoUpdate(iRewardToken1, 0, callTimestamp.safeCastTo32());

    staking.addRewardToken(iRewardToken1, 0, 0, true, 10000000, 100, 20);

    (
      uint64 ONE,
      uint160 rewardsPerSecond,
      uint32 rewardsEndTimestamp,
      uint224 index,
      uint32 lastUpdatedTimestamp
    ) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(ONE), 1 ether);
    assertEq(rewardsPerSecond, 0);
    assertEq(uint256(rewardsEndTimestamp), callTimestamp);
    assertEq(index, 1 ether);
    assertEq(uint256(lastUpdatedTimestamp), callTimestamp);
  }

  function test__addRewardToken_end_time_not_affected_by_other_transfers() public {
    // Prepare to transfer reward tokens
    rewardToken1.mint(address(this), 20 ether);
    rewardToken1.approve(address(staking), 10 ether);

    // transfer some token to staking beforehand
    rewardToken1.transfer(address(staking), 10 ether);

    uint256 callTimestamp = block.timestamp;
    staking.addRewardToken(iRewardToken1, 0.1 ether, 10 ether, true, 10000000, 100, 0);

    // RewardsEndTimeStamp shouldnt be affected by previous token transfer
    (, , uint32 rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(rewardsEndTimestamp), callTimestamp + 100);

    // Confirm token transfer
    assertEq(rewardToken1.balanceOf(address(this)), 0);
    assertEq(rewardToken1.balanceOf(address(staking)), 20 ether);
  }

  function testFail__addRewardToken_token_exists() public {
    // Prepare to transfer reward tokens
    rewardToken1.mint(address(this), 20 ether);
    rewardToken1.approve(address(staking), 20 ether);

    staking.addRewardToken(iRewardToken1, 0.1 ether, 10 ether, true, 10000000, 100, 0);

    vm.expectRevert(MultiRewardStaking.RewardTokenAlreadyExist.selector);
    staking.addRewardToken(iRewardToken1, 0.1 ether, 10 ether, true, 10000000, 100, 0);
  }

  function testFail__addRewardToken_rewardsToken_is_stakingToken() public {
    staking.addRewardToken(IERC20(address(stakingToken)), 0.1 ether, 10 ether, true, 10000000, 100, 0);
  }

  function testFail__addRewardToken_0_rewardsSpeed_non_0_amount() public {
    // Prepare to transfer reward tokens
    rewardToken1.mint(address(this), 1 ether);
    rewardToken1.approve(address(staking), 1 ether);

    staking.addRewardToken(iRewardToken1, 0, 1 ether, true, 10000000, 100, 20);
  }

  function testFail__addRewardToken_escrow_with_0_percentage() public {
    staking.addRewardToken(iRewardToken1, 0.1 ether, 10 ether, true, 0, 100, 0);
  }

  function testFail__addRewardToken_escrow_with_more_than_100_percentage() public {
    staking.addRewardToken(iRewardToken1, 0.1 ether, 10 ether, true, 1e19, 100, 0);
  }

  function testFail__addRewardToken_0_rewardsSpeed_amount_larger_0_and_0_shares() public {
    staking.addRewardToken(iRewardToken1, 0, 10, false, 0, 0, 0);
  }

  /*//////////////////////////////////////////////////////////////
                        CHANGE REWARDS SPEED LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__changeRewardSpeed() public {
    _addRewardToken(rewardToken1);

    stakingToken.mint(alice, 1 ether);
    stakingToken.mint(bob, 1 ether);

    vm.prank(alice);
    stakingToken.approve(address(staking), 1 ether);
    vm.prank(bob);
    stakingToken.approve(address(staking), 1 ether);

    vm.prank(alice);
    staking.deposit(1 ether);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);
    // Double Accrual (from original)
    staking.changeRewardSpeed(iRewardToken1, 0.2 ether);

    // 30% of rewards paid out
    vm.warp(block.timestamp + 10);
    // Half Accrual (from original)
    staking.changeRewardSpeed(iRewardToken1, 0.05 ether);
    vm.prank(bob);
    staking.deposit(1 ether);

    // 50% of rewards paid out
    vm.warp(block.timestamp + 40);

    vm.prank(alice);
    staking.withdraw(1 ether);

    // Check Alice RewardsState
    (, , , uint224 index, uint32 lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 5 ether);

    assertEq(staking.userIndex(alice, iRewardToken1), index);
    assertEq(staking.accruedRewards(alice, iRewardToken1), 4 ether);

    vm.prank(bob);
    staking.withdraw(1 ether);

    // Check Bobs RewardsState
    (, , , index, lastUpdatedTimestamp) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(index), 5 ether);

    assertEq(staking.userIndex(bob, iRewardToken1), index);
    assertEq(staking.accruedRewards(bob, iRewardToken1), 1 ether);
  }

  function test__changeRewardSpeed2() public {
    _addRewardToken(rewardToken1);

    stakingToken.mint(alice, 1 ether);

    vm.prank(alice);
    stakingToken.approve(address(staking), 1 ether);
    vm.prank(alice);
    staking.deposit(1 ether);

    (, , uint32 rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    // StartTime 1, Rewards 10e18, RewardsPerSecond 0.1e18, RewardsEndTimeStamp 101
    assertEq(rewardsEndTimestamp, 101);

    staking.changeRewardSpeed(iRewardToken1, 0.5 ether);
    (, , rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    // StartTime 1, Rewards 10e18, RewardsPerSecond 0.5e18, RewardsEndTimeStamp 21
    assertEq(rewardsEndTimestamp, 21);

    vm.warp(block.timestamp + 10);

    // 50% paid out, CallTime 11, Rewards 5e18, RewardsPerSecond 0.1e18, RewardsEndTimeStamp 61
    staking.changeRewardSpeed(iRewardToken1, 0.1 ether);
    (, , rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    assertEq(rewardsEndTimestamp, 61);
  }

  function testFail__changeRewardSpeed_to_0() public {
    _addRewardToken(rewardToken1);
    staking.changeRewardSpeed(iRewardToken1, 0);
  }

  function testFail__changeRewardSpeed_from_0() public {
    _addRewardTokenWithZeroRewardsSpeed(rewardToken1);
    staking.changeRewardSpeed(iRewardToken1, 1);
  }

  function testFail__changeRewardSpeed_reward_doesnt_exist() public {
    staking.changeRewardSpeed(iRewardToken1, 1);
  }

  function testFail__changeRewardSpeed_nonOwner() public {
    _addRewardToken(rewardToken1);
    vm.prank(alice);
    staking.changeRewardSpeed(iRewardToken1, 1);
  }

  /*//////////////////////////////////////////////////////////////
                        FUND REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__fundReward() public {
    _addRewardToken(rewardToken1);
    rewardToken1.mint(address(this), 10 ether);
    rewardToken1.approve(address(staking), 10 ether);

    (, , uint32 oldRewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);

    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardInfoUpdate(iRewardToken1, 0.1 ether, oldRewardsEndTimestamp + 100);

    staking.fundReward(iRewardToken1, 10 ether);

    // RewardsEndTimeStamp should take new token into account
    (, , uint32 rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(rewardsEndTimestamp), uint256(oldRewardsEndTimestamp) + 100);

    // Confirm token transfer
    assertEq(rewardToken1.balanceOf(address(this)), 0);
    assertEq(rewardToken1.balanceOf(address(staking)), 20 ether);
  }

  function test__fundReward_0_rewardsSpeed() public {
    _addRewardTokenWithZeroRewardsSpeed(rewardToken1);

    rewardToken1.mint(address(this), 10 ether);
    rewardToken1.approve(address(staking), 10 ether);

    stakingToken.mint(address(this), 1 ether);
    stakingToken.approve(address(staking), 1 ether);

    staking.deposit(1 ether);

    (, , uint32 oldRewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);

    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardInfoUpdate(iRewardToken1, 0, oldRewardsEndTimestamp);

    staking.fundReward(iRewardToken1, 10 ether);

    // RewardsEndTimeStamp should take new token into account
    (, , uint32 rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(rewardsEndTimestamp), uint256(oldRewardsEndTimestamp));

    // Confirm token transfer
    assertEq(rewardToken1.balanceOf(address(this)), 0);
    assertEq(rewardToken1.balanceOf(address(staking)), 10 ether);
  }

  function test__fundReward_end_time_not_affected_by_other_transfers() public {
    // Prepare to transfer reward tokens
    _addRewardToken(rewardToken1);
    rewardToken1.mint(address(this), 20 ether);
    rewardToken1.approve(address(staking), 10 ether);

    // transfer some token to staking beforehand
    rewardToken1.transfer(address(staking), 10 ether);

    (, , uint32 oldRewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);

    staking.fundReward(iRewardToken1, 10 ether);

    // RewardsEndTimeStamp shouldnt be affected by previous token transfer
    (, , uint32 rewardsEndTimestamp, , ) = staking.rewardInfos(iRewardToken1);
    assertEq(uint256(rewardsEndTimestamp), uint256(oldRewardsEndTimestamp) + 100);

    // Confirm token transfer
    assertEq(rewardToken1.balanceOf(address(this)), 0);
    assertEq(rewardToken1.balanceOf(address(staking)), 30 ether);
  }

  function testFail__fundReward_zero_amount() public {
    _addRewardToken(rewardToken1);

    staking.fundReward(iRewardToken1, 0);
  }

  function testFail__fundReward_no_rewardsToken() public {
    staking.fundReward(IERC20(address(0)), 10 ether);
  }

  function testFail__fundReward_0_rewardsSpeed_zero_shares() public {
    _addRewardTokenWithZeroRewardsSpeed(rewardToken1);

    rewardToken1.mint(address(this), 10 ether);
    rewardToken1.approve(address(staking), 10 ether);

    staking.fundReward(iRewardToken1, 10 ether);
  }

  /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__claim() public {
    // Prepare array for `claimRewards`
    IERC20[] memory rewardsTokenKeys = new IERC20[](1);
    rewardsTokenKeys[0] = iRewardToken1;

    _addRewardToken(rewardToken1);
    stakingToken.mint(alice, 5 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 5 ether);
    staking.deposit(1 ether);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardsClaimed(alice, iRewardToken1, 1 ether, false);

    staking.claimRewards(alice, rewardsTokenKeys);

    assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
    assertEq(rewardToken1.balanceOf(alice), 1 ether);
  }

  function test__claim_0_rewardsSpeed() public {
    // Prepare array for `claimRewards`
    IERC20[] memory rewardsTokenKeys = new IERC20[](1);
    rewardsTokenKeys[0] = iRewardToken1;

    _addRewardTokenWithZeroRewardsSpeed(rewardToken1);
    rewardToken1.mint(address(this), 5 ether);
    rewardToken1.approve(address(staking), 5 ether);
    stakingToken.mint(alice, 1 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 1 ether);
    staking.deposit(1 ether);
    vm.stopPrank();

    staking.fundReward(iRewardToken1, 5 ether);

    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardsClaimed(alice, iRewardToken1, 5 ether, false);

    staking.claimRewards(alice, rewardsTokenKeys);

    assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
    assertEq(rewardToken1.balanceOf(alice), 5 ether);
  }

  function test__claim_multiple_token_with_escrows() public {
    // Prepare array for `claimRewards`
    IERC20[] memory rewardsTokenKeys = new IERC20[](2);
    rewardsTokenKeys[0] = iRewardToken1;
    rewardsTokenKeys[1] = iRewardToken2;
    _addRewardToken(rewardToken1);
    _addRewardTokenWithEscrow(rewardToken2);

    stakingToken.mint(alice, 5 ether);

    vm.startPrank(alice);
    stakingToken.approve(address(staking), 5 ether);
    staking.deposit(1 ether);

    // 10% of rewards paid out
    vm.warp(block.timestamp + 10);

    vm.expectEmit(false, false, false, true, address(staking));
    emit RewardsClaimed(alice, iRewardToken1, 1 ether, false);
    emit RewardsClaimed(alice, iRewardToken2, 1 ether, true);

    staking.claimRewards(alice, rewardsTokenKeys);

    assertEq(staking.accruedRewards(alice, iRewardToken1), 0);
    assertEq(rewardToken1.balanceOf(alice), 1 ether);

    assertEq(staking.accruedRewards(alice, iRewardToken2), 0);
    assertEq(rewardToken2.balanceOf(alice), 0.9 ether);

    // Check escrow
    bytes32[] memory escrowIds = escrow.getEscrowIdsByUser(alice);
    (IERC20 token, , , , , uint256 balance, address account) = escrow.escrows(escrowIds[0]);

    assertEq(rewardToken2.balanceOf(address(escrow)), 0.1 ether);
    assertEq(address(token), address(rewardToken2));
    assertEq(account, alice);
    assertEq(balance, 0.1 ether);
  }

  function testFail__claim_non_existent_rewardsToken() public {
    IERC20[] memory rewardsTokenKeys = new IERC20[](1);

    vm.prank(alice);
    staking.claimRewards(alice, rewardsTokenKeys);
  }

  function testFail__claim_non_existent_reward() public {
    IERC20[] memory rewardsTokenKeys = new IERC20[](1);

    vm.prank(alice);
    staking.claimRewards(alice, rewardsTokenKeys);
  }
}
