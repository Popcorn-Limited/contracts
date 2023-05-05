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
    // Polygon - wstEth-ETH vault
    testConfigs.push(
      BeefyTestConfig(0x1d81c50d5aB5f095894c41B41BA49B9873033399, 0x4Cc44C30f4d3789AE8d8e9C8dE409D11c79C5CE3, "polygon")
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
