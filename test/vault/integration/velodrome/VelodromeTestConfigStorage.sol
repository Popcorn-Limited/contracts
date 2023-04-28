// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct VelodromeTestConfig {
    address gauge;
}

contract VelodromeTestConfigStorage is ITestConfigStorage {
    VelodromeTestConfig[] internal testConfigs;

    constructor() {
        // Optimism - wETH-OP
        testConfigs.push(
            VelodromeTestConfig(0x2f733b00127449fcF8B5a195bC51Abb73B7F7A75)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gauge);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
