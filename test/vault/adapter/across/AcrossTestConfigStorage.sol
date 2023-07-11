// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct AcrossTestConfig {
    address acrossHop;
    address acrossDistributor;
}

contract AcrossTestConfigStorage is ITestConfigStorage {
    AcrossTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet Across Hop Pool - 0xc186fA914353c44b2E33eBE05f21846F1048bEda
        // Mainnet Across Accelerating Distributor - 0x9040e41eF5E8b281535a96D9a48aCb8cfaBD9a48
        testConfigs.push(
            AcrossTestConfig(
                0xc186fA914353c44b2E33eBE05f21846F1048bEda,
                0x9040e41eF5E8b281535a96D9a48aCb8cfaBD9a48
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].acrossHop,
                testConfigs[i].acrossDistributor
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
