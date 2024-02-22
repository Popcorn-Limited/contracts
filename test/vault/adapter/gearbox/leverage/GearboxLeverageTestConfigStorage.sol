// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct GearboxLeverageTestConfig {
  address _creditFacade;
  address _creditManager;
}

contract GearboxLeverageTestConfigStorage {
  GearboxLeverageTestConfig[] internal testConfigs;

  constructor() {
    // Mainnet
    testConfigs.push(GearboxLeverageTestConfig(
      0x958cBC4AEA076640b5D9019c61e7F78F4F682c0C,
      0x3EB95430FdB99439A86d3c6D7D01C3c561393556
    ));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i]._creditFacade, testConfigs[i]._creditManager);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
