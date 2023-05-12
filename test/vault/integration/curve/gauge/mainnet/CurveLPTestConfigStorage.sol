// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../../abstract/ITestConfigStorage.sol";

struct CurveLPTestConfig {
    uint poolId;
}

contract CurveLPTestConfigStorage is ITestConfigStorage {
    CurveLPTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(CurveLPTestConfig(
           0  // 3CRV pool
        ));
    // TODO: add another test for Metapools
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        CurveLPTestConfig memory config = testConfigs[i];
        return abi.encode(
            config.poolId
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
