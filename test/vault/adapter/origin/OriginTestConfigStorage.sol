// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct OriginTestConfig {
    address wAsset;
    uint256 defaultAmount;
    uint256 raise;
    uint256 maxAssets;
    uint256 maxShares;
    address assetWhale;
}

contract OriginTestConfigStorage is ITestConfigStorage {
    OriginTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            OriginTestConfig(
                0xD2af830E8CBdFed6CC11Bab697bB25496ed6FA62,
                1e18,
                1000e18,
                1000e18,
                100e27,
                0x70fCE97d671E81080CA3ab4cc7A59aAc2E117137
            )
        );
        testConfigs.push(
            OriginTestConfig(
                0xDcEe70654261AF21C44c093C300eD3Bb97b78192,
                1e18,
                10e18,
                10e18,
                10e27,
                0xc055De577ce2039E6D35621E3a885df9Bb304AB9
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].wAsset,
                testConfigs[i].defaultAmount,
                testConfigs[i].raise,
                testConfigs[i].maxAssets,
                testConfigs[i].maxShares,
                testConfigs[i].assetWhale
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
