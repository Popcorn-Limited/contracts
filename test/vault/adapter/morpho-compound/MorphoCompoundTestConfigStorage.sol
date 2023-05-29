// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct MorphoCompoundTestConfig {
    address poolToken;
    address morpho;
    address lens;
}

contract MorphoCompoundTestConfigStorage is ITestConfigStorage {
    MorphoCompoundTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet - Compound USD
        testConfigs.push(
            MorphoCompoundTestConfig(
                0x39AA39c021dfbaE8faC545936693aC917d5E7563,
                0x8888882f8f843896699869179fB6E4f7e3B58888,
                0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].poolToken,
                testConfigs[i].morpho,
                testConfigs[i].lens
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
