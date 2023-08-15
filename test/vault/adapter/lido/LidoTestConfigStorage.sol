// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LidoTestConfig {
    uint256 slippage;
    uint256 pid;
}

contract LidoTestConfigStorage is ITestConfigStorage {
    LidoTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            LidoTestConfig(1e15 , 1) // 10 BPS
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].slippage, testConfigs[i].pid);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
