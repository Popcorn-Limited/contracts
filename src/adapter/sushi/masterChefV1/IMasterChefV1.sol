// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IMasterChefV1 {
  struct PoolInfo {
    address lpToken;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accSushiPerShare;
  }

  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  function poolInfo(uint256 pid) external view returns (IMasterChefV1.PoolInfo memory);

  function userInfo(uint256 pid, address adapterAddress) external view returns (IMasterChefV1.UserInfo memory);

  function totalAllocPoint() external view returns (uint256);

  function deposit(uint256 _pid, uint256 _amount) external;

  function withdraw(uint256 _pid, uint256 _amount) external;

  function enterStaking(uint256 _amount) external;

  function leaveStaking(uint256 _amount) external;

  function emergencyWithdraw(uint256 _pid) external;

  function pendingSushi(uint256 _pid, address _user) external view returns (uint256);
}
