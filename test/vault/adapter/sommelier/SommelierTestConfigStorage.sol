// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct SommelierTestConfig {
    address vault;
}

contract SommelierTestConfigStorage is ITestConfigStorage {
    SommelierTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet - Turbo stETH
        testConfigs.push(
            SommelierTestConfig(0xfd6db5011b171B05E1Ea3b92f9EAcaEEb055e971)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].vault);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
