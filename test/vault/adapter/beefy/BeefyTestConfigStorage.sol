// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../abstract/ITestConfigStorage.sol";

struct BeefyTestConfig {
  address beefyVault;
  address beefyBooster;
  string network;
}

contract BeefyTestConfigStorage is ITestConfigStorage {
  BeefyTestConfig[] internal testConfigs;

  constructor() {
    // Polygon - MaticX-​bbaWMATIC vault
    testConfigs.push(
      BeefyTestConfig(0x4C98CB046c3eb7e3ae7Eb49a33D6f3386Ec2b9D9, 0x2e5598608A4436dBb9c34CE6862B5AF882F49a6B, "polygon")
    );

    // Ethereum - stEth-ETH vault
    testConfigs.push(BeefyTestConfig(0xa7739fd3d12ac7F16D8329AF3Ee407e19De10D8D, address(0), "mainnet"));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].beefyVault, testConfigs[i].beefyBooster, testConfigs[i].network);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
