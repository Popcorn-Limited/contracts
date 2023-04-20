// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct AaveV3TestConfig {
  address asset;
  address aaveDataProvider;
}

contract AaveV3TestConfigStorage is ITestConfigStorage {
  AaveV3TestConfig[] internal testConfigs;

  constructor() {
    // Polygon - wETH
    testConfigs.push(
      AaveV3TestConfig(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, 0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654)
    );
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].asset, testConfigs[i].aaveDataProvider);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
