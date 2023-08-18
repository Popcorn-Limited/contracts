// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../abstract/ITestConfigStorage.sol";

struct BalancerGaugeTestConfig {
  address asset;
}

contract BalancerGaugeTestConfigStorage is ITestConfigStorage {
  BalancerGaugeTestConfig[] internal testConfigs;

  constructor() {
    // Mainnet - USDC-DAI-USDT Gauge
    testConfigs.push(BalancerGaugeTestConfig(0x79eF6103A513951a3b25743DB509E267685726B7));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].asset);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
