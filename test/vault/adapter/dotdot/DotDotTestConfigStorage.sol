// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct DotDotTestConfig {
    address asset;
}

contract DotDotTestConfigStorage is ITestConfigStorage {
    DotDotTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            DotDotTestConfig(0x3e33ec615eB41148785653c119835Bd224Fd2d1B)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
