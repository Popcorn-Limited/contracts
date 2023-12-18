// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IAuraBooster {
  function poolInfo(
    uint256 _pid
  )
    external
    view
    returns (address lpToken, address token, address gauge, address crvRewards, address stash, bool shutdown);

  function deposit(uint256 _pid, uint256 _amount, bool _claim) external;

  function stakerRewards() external view returns (address);
}

interface IAuraRewards {
  function getReward() external;

  function withdrawAndUnwrap(uint256 _amount, bool _claim) external;

  function balanceOf(address _user) external view returns (uint256);
}

interface IAuraStaking {
  function crv() external view returns (address);

  function cvx() external view returns (address);
}
