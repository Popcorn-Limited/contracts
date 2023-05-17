// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../../abstract/ITestConfigStorage.sol";

struct CompoundV3TestConfig {
  address cToken;
  address cometRewarder;
}

contract CompoundV3TestConfigStorage is ITestConfigStorage {
  CompoundV3TestConfig[] internal testConfigs;

  constructor() {
    // Mainnet - cUSDCv3
    testConfigs.push(
      CompoundV3TestConfig(
        0xc3d688B66703497DAA19211EEdff47f25384cdc3,
        0x1B0e765F6224C21223AeA2af16c1C46E38885a40
      )
    );
  }

  function getTestConfig(uint256 i) public view returns (bytes memory) {
    return abi.encode(testConfigs[i].cToken, testConfigs[i].cometRewarder);
  }

  function getTestConfigLength() public view returns (uint256) {
    return testConfigs.length;
  }
}
