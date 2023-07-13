// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ITestConfigStorage } from "../abstract/ITestConfigStorage.sol";

struct GmdTestConfig {
    address asset;
    address vault;
    uint256 poolId;
}

contract GmdTestConfigStorage is ITestConfigStorage {
    GmdTestConfig[] internal testConfigs;

    constructor() {
        // USDC
        testConfigs.push(
            GmdTestConfig(
                0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8,
                0x8080B5cE6dfb49a6B86370d6982B3e2A86FBBb08,
                uint256(0)
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].vault, testConfigs[i].poolId);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
