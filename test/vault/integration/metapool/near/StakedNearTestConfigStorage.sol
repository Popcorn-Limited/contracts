// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct StakedNearTestConfig {
    address asset;
}

contract StakedNearTestConfigStorage is ITestConfigStorage {
    StakedNearTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            StakedNearTestConfig(0xC42C30aC6Cc15faC9bD938618BcaA1a1FaE8501d)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
