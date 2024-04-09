// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct PendleTestConfig {
    address asset;
    address pendleMarket;
}

contract PendleTestConfigStorage is ITestConfigStorage {
    PendleTestConfig[] internal testConfigs;

    constructor() {
        // wstETH
        testConfigs.push(
            PendleTestConfig(
                0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, // wstETH
                0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2 // stETH 26DIC24
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].pendleMarket);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
