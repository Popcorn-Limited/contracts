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
    testConfigs.push(BalancerGaugeTestConfig(0x5612876e6F6cA370d93873FE28c874e89E741fB9));
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].asset);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
