// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct MetaPoolTestConfig {
    address pool;
}

contract MetaPoolTestConfigStorage is ITestConfigStorage {
    MetaPoolTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            MetaPoolTestConfig(0x534BACf1126f60EA513F796a3377ff432BE62cf9)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].pool);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
