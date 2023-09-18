// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../../adapter/abstract/ITestConfigStorage.sol";

struct RocketPoolTestConfig {
  address uniRouter;
  uint24 uniSwapFee;
  string network;
}

contract RocketpoolTestConfigStorage is ITestConfigStorage {
  TestConfig[] public testConfigs;

  constructor() {
    testConfigs.push(
      RocketPoolTestConfig(
        0xE592427A0AEce92De3Edee1F18E0157C05861564,
        500,
        "mainnet"
      )
    );
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
