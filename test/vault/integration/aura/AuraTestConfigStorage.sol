pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../abstract/ITestConfigStorage.sol";

struct AuraTestConfig {
  uint256 pid;
}

contract AuraTestConfigStorage is ITestConfigStorage {
  AuraTestConfig[] internal testConfigs;

  constructor() {
    testConfigs.push(AuraTestConfig(0));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].pid);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
