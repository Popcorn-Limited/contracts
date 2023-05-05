// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../abstract/ITestConfigStorage.sol";

struct OusdTestConfig {
  address wousd;
}

contract OusdTestConfigStorage is ITestConfigStorage {
  OusdTestConfig[] internal testConfigs;

  constructor() {
    // Mainnet - wETH
    testConfigs.push(OusdTestConfig(0xD2af830E8CBdFed6CC11Bab697bB25496ed6FA62));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].wousd);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
