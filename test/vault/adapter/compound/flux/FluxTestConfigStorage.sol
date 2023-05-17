// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct FluxTestConfig {
  address asset;
}

contract FluxTestConfigStorage is ITestConfigStorage {
  FluxTestConfig[] internal testConfigs;

  constructor() {
    // Mainnet - cDAI
    testConfigs.push(FluxTestConfig(0xe2bA8693cE7474900A045757fe0efCa900F6530b));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].asset);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
