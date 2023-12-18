// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IConvexBooster {
  function deposit(
    uint256 pid,
    uint256 amount,
    bool stake
  ) external;

  function withdraw(uint256 pid, uint256 amount) external;

  function poolInfo(uint256 pid)
    external
    view
    returns (
      address lpToken,
      address token,
      address gauge,
      address crvRewards,
      address stash,
      bool shutdown
    );
}

interface IConvexRewards {
  function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

  function getReward(address _account, bool _claimExtras) external returns (bool);

  function balanceOf(address addr) external view returns (uint256);

  function stakingToken() external view returns (address);

  function extraRewards(uint256 index) external view returns (IRewards);

  function extraRewardsLength() external view returns (uint256);

  function rewardToken() external view returns (address);
}

interface IRewards {
  function rewardToken() external view returns (address);
}
