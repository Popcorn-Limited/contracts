// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IBeefyVault {
  function want() external view returns (address);

  function deposit(uint256 _amount) external;

  function withdraw(uint256 _shares) external;

  function withdrawAll() external;

  function balanceOf(address _account) external view returns (uint256);

  //Returns total balance of underlying token in the vault and its strategies
  function balance() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function earn() external;

  function getPricePerFullShare() external view returns (uint256);

  function strategy() external view returns (address);
}

interface IBeefyBooster {
  function earned(address _account) external view returns (uint256);

  function balanceOf(address _account) external view returns (uint256);

  function stakedToken() external view returns (address);

  function rewardToken() external view returns (address);

  function periodFinish() external view returns (uint256);

  function rewardPerToken() external view returns (uint256);

  function stake(uint256 _amount) external;

  function withdraw(uint256 _shares) external;

  function exit() external;

  function getReward() external;
}

interface IBeefyBalanceCheck {
  function balanceOf(address _account) external view returns (uint256);
}

interface IBeefyStrat {
  function withdrawFee() external view returns (uint256);

  function withdrawalFee() external view returns (uint256);
}
