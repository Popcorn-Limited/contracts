// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct RadiantTestConfig {
    address asset;
    address radiantDataProvider;
}

contract RadiantTestConfigStorage is ITestConfigStorage {
    RadiantTestConfig[] internal testConfigs;

    constructor() {
        // Arbitrum - rDAI
        testConfigs.push(
            RadiantTestConfig(
                0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1,
                0x596B0cc4c5094507C50b579a662FE7e7b094A2cC
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].asset,
                testConfigs[i].radiantDataProvider
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
