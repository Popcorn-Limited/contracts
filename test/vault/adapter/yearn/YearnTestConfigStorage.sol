// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct YearnTestConfig {
    address asset;
    uint256 maxLoss;
}

contract YearnTestConfigStorage is ITestConfigStorage {
    YearnTestConfig[] internal testConfigs;

    constructor() {
        // USDC
        testConfigs.push(
            YearnTestConfig(
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                uint256(1)
            )
        );

        // WETH
        // testConfigs.push(YearnTestConfig(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, uint256(1)));

        // DAI
        testConfigs.push(
            YearnTestConfig(
                0x6B175474E89094C44Da98b954EedeAC495271d0F,
                uint256(1)
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].maxLoss);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
