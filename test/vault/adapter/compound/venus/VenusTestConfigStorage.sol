// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct VenusTestConfig {
    address asset;
}

contract VenusTestConfigStorage is ITestConfigStorage {
    VenusTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            VenusTestConfig(0x334b3eCB4DCa3593BCCC3c7EBD1A1C1d1780FBF1)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
