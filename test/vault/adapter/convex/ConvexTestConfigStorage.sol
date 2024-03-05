// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../abstract/ITestConfigStorage.sol";

struct ConvexTestConfig {
  uint256 pid;
  address curvePool;
  address curveLpToken;
}

contract ConvexTestConfigStorage is ITestConfigStorage {
  ConvexTestConfig[] internal testConfigs;

  constructor() {
    // Mainnet - wETH
    testConfigs.push(ConvexTestConfig(
      289,
      0x625E92624Bc2D88619ACCc1788365A69767f6200,
      0x625E92624Bc2D88619ACCc1788365A69767f6200
    ));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].pid, testConfigs[i].curvePool, testConfigs[i].curveLpToken);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
