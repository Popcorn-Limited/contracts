// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct GearboxLeverageTestConfig {
  address _creditFacade;
  address _creditManager;
  address _strategyAdapter;
}

contract GearboxLeverageTestConfigStorage is ITestConfigStorage {
  GearboxLeverageTestConfig[] internal testConfigs;

  constructor() {
    // Mainnet
    testConfigs.push(GearboxLeverageTestConfig(
      0x9Ab55e5c894238812295A31BdB415f00f7626792,
      0x3EB95430FdB99439A86d3c6D7D01C3c561393556,
      0x93C54c10a8DC03e7773Ca1d1575044adF62fB53D
    ));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i]._creditFacade, testConfigs[i]._creditManager, testConfigs[i]._strategyAdapter);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
