// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct GearboxPassivePoolTestConfig {
  uint256 _pid;
}

contract GearboxPassivePoolTestConfigStorage {
  GearboxPassivePoolTestConfig[] internal testConfigs;

  constructor() {
    // DAI
    testConfigs.push(GearboxPassivePoolTestConfig(0));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i]._pid);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
