// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IGauge {
  function stake() external view returns (address);

  function solid() external view returns (address);

  function balanceOf(address _user) external view returns (uint256);

  function depositAndOptIn(uint256 _amount, uint256 _tokenId, address[] memory _optInPools) external;

  function withdraw(uint256 _amount) external;

  function getReward(address _account, address[] memory _tokens) external;

  function rewardsListLength() external view returns (uint256);

  function rewards(uint256 _index) external view returns (address);

  function optIn(address[] memory _optTokens) external;

  function optOut(address[] memory _optTokens) external;
}

interface ILpToken {
  function token0() external view returns (address);

  function token1() external view returns (address);
}