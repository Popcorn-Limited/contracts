// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct IonDepositorTestConfig {
    address asset;
    address ionPool;
    address whitelist;
    address ionOwner;
}

contract IonDepositorTestConfigStorage is ITestConfigStorage {
    IonDepositorTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            IonDepositorTestConfig(
                0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
                0x0000000000eaEbd95dAfcA37A39fd09745739b78,
                0x7E317f99aA313669AaCDd8dB3927ff3aCB562dAD,
                0x0000000000417626Ef34D62C4DC189b021603f2F
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].asset,
                testConfigs[i].ionPool,
                testConfigs[i].whitelist,
                testConfigs[i].ionOwner
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
