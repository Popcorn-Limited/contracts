// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct UnionPirexTestConfig {
    address vault;
}

contract UnionPirexTestConfigStorage is ITestConfigStorage {
    UnionPirexTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet - Union Pirex Vault (uCVX)
        testConfigs.push(
            UnionPirexTestConfig(
                0x8659Fc767cad6005de79AF65dAfE4249C57927AF
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].vault
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
