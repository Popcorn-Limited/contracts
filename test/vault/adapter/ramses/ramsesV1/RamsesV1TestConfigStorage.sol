// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct RamsesTestConfig {
    address gauge;
}

contract RamsesTestConfigStorage is ITestConfigStorage {
    RamsesTestConfig[] internal testConfigs;

    constructor() {
        // Arbitrum - FRAX-DOLA
        testConfigs.push(
            RamsesTestConfig(0xF8719BC4a1A81969F00233a8D9409755d4366d28)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gauge);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
