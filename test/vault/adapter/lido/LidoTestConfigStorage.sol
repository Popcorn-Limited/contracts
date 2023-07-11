// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LidoTestConfig {
    address asset;
    uint256 pid;
}

contract LidoTestConfigStorage is ITestConfigStorage {
    LidoTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            LidoTestConfig(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 , 1)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].pid);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
