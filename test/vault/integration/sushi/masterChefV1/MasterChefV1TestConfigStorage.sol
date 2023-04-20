pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct MasterChefV1TestConfig {
  uint256 pid;
  address rewardsToken;
}

contract MasterChefV1TestConfigStorage is ITestConfigStorage {
  MasterChefV1TestConfig[] internal testConfigs;

  constructor() {
    testConfigs.push(MasterChefV1TestConfig(2, 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].pid, testConfigs[i].rewardsToken);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
