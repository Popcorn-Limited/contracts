// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct CurveLPTestConfig {
    uint poolId;
}

contract CurveLPTestConfigStorage is ITestConfigStorage {
    CurveLPTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            CurveLPTestConfig(
                0 // 3CRV pool
            )
        );
        testConfigs.push(
            CurveLPTestConfig(
                24 // eCRV pool
            )
        );
        testConfigs.push(
            CurveLPTestConfig(
                92 // Badger / WBTC pool
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        CurveLPTestConfig memory config = testConfigs[i];
        return abi.encode(config.poolId);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
