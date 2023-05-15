// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct YearnFactoryTestConfig {
    address gauge;
    uint256 maxLoss;
}

contract YearnFactoryTestConfigStorage is ITestConfigStorage {
    YearnFactoryTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            YearnFactoryTestConfig(
                0x06f691180F643B35E3644a2296a4097E1f577d0d,
                1
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gauge, testConfigs[i].maxLoss);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
