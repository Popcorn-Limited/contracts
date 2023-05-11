// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct EllipsisLpStakingTestConfig {
    address asset;
    uint256 pId;
}

contract EllipsisLpStakingTestConfigStorage is ITestConfigStorage {
    EllipsisLpStakingTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            EllipsisLpStakingTestConfig(0xaF4dE8E872131AE328Ce21D909C74705d3Aaf452, 0)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].pId);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
