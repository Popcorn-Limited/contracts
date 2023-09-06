// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../../adapter/abstract/ITestConfigStorage.sol";

struct RocketPoolTestConfig {
  address rocketStorageAddress;
  address wETH;
  address uniRouter;
  uint24 uniSwapFee;
  string network;
}

contract RocketpoolTestConfigStorage is ITestConfigStorage {
  RocketPoolTestConfig[] internal testConfigs;

  constructor() {
    testConfigs.push(
      RocketPoolTestConfig(
        0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46,
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
        0xE592427A0AEce92De3Edee1F18E0157C05861564,
        500,
        "mainnet"
      )
    );
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(
      testConfigs[i].rocketStorageAddress,
      testConfigs[i].wETH,
      testConfigs[i].uniRouter,
      testConfigs[i].uniSwapFee,
      testConfigs[i].network
    );
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
