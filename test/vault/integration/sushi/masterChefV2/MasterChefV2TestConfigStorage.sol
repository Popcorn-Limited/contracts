pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct MasterChefV2TestConfig {
  uint256 pid;
  address rewardsToken;
}

contract MasterChefV2TestConfigStorage is ITestConfigStorage {
  MasterChefV2TestConfig[] internal testConfigs;

  constructor() {
    testConfigs.push(MasterChefV2TestConfig(60, 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].pid, testConfigs[i].rewardsToken);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
