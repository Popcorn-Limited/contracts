// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct SolidlyTestConfig {
    address gauge;
}

contract SolidlyTestConfigStorage is ITestConfigStorage {
    SolidlyTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet - wETH
        testConfigs.push(
            SolidlyTestConfig(0x84674cFFB6146D19b986fC88EC70a441b570A45B)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gauge);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
