// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LidoTestConfig {
    address asset;
}

contract LidoTestConfigStorage is ITestConfigStorage {
    LidoTestConfig[] internal testConfigs;

    constructor() {
        // USDC
        // testConfigs.push(LidoTestConfig(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));

        // WETH
        testConfigs.push(
            LidoTestConfig(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
