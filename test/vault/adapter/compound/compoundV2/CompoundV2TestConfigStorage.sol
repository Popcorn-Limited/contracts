// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct CompoundV2TestConfig {
  address asset;
}

contract CompoundV2TestConfigStorage is ITestConfigStorage {
  CompoundV2TestConfig[] internal testConfigs;

  constructor() {
    // Mainnet - cDAI
    testConfigs.push(CompoundV2TestConfig(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].asset);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
