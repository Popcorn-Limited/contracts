// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct IdleTestConfig {
    address cdo;
}

contract IdleTestConfigStorage is ITestConfigStorage {
    IdleTestConfig[] internal testConfigs;

    constructor() {
        address cdo = 0x9C13Ff045C0a994AF765585970A5818E1dB580F8; // DAI staking

        testConfigs.push(IdleTestConfig(cdo));
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].cdo);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
