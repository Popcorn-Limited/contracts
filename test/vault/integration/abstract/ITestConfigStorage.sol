// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface ITestConfigStorage {
  function getTestConfig(uint256 i) external view returns (bytes memory);

  function getTestConfigLength() external view returns (uint256);
}
