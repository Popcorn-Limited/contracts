// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage, TestConfig} from "../../base/interfaces/ITestConfigStorage.sol";
import {IERC20, IBaseAdapter, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapterTest.sol";

struct RocketPoolTestConfig {
    address uniRouter;
    uint24 uniSwapFee;
    string network;
}

contract RocketpoolTestConfigStorage is ITestConfigStorage {
    TestConfig[] public testConfigs;
    AdapterConfig[] public adapterConfigs;
    ProtocolConfig[] public protocolConfigs;

     IERC20 public constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IERC20[] public rewardTokens;

    constructor() {
        // Config 0
        testConfigs.push(TestConfig({
    asset: WETH,
    delta: 10,
    testId. "RocketPool WETH",
    network: "mainnet",
    blockNumber: 18104376;
    defaultAmount: 1e18,
    minDeposit: 1e18,
     maxDeposit: 1e18,
     minWithdraw: 1e18,
     maxWithdraw: 1e18,
    optionalData = ""
}));
        adapterConfigs.push(
          AdapterConfig({
      underlying: WETH,
      lpToken: IERC20(address(0)),
      useLpToken: false,
      rewardTokens: rewardTokens,
      owner: address(this)
    }));
        protocolConfigs.push(
          ProtocolConfig({
      registry: address (0),
      protocolInitData: abi.encode(
        0xE592427A0AEce92De3Edee1F18E0157C05861564, // UniRouter
        24 // UniSwapFee
      )
    }));
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
