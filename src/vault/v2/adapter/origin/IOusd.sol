// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IWousd {
  function asset() external view returns (address);

  function convertToAssets(uint256 _shares) external view returns (uint256);

  function deposit(uint256 _amount, address _receiver) external;

  function redeem(uint256 _shares, address _receiver, address _owner) external;

  function balanceOf(address _user) external view returns (uint256);
}
