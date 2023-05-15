// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct StargateLpStakingTestConfig {
  uint256 stakingPid;
}

contract StargateLpStakingTestConfigStorage is ITestConfigStorage {
  StargateLpStakingTestConfig[] internal testConfigs;

  constructor() {
    // Ethereum - sUSDC
    // testConfigs.push(StargateLpStakingTestConfig(0));
    // Ethereum - sUSDT
    testConfigs.push(StargateLpStakingTestConfig(1));
    // Ethereum - sDAI
    // testConfigs.push(StargateLpStakingTestConfig(3));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].stakingPid);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
