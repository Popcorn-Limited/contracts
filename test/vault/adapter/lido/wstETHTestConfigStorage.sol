// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LevWstETHTestConfig {
    address awstETH; // interest token
    address vdWETH; // variable debt token
    address lendingPool;
    address dataProvider; // aaveDataProvider contract
    address poolAddressesProvider;
    uint256 slippage;
    uint256 slippageCap;
    uint256 targetLTV;
    uint256 maxLTV;
}

contract LevWstETHTestConfigStorage is ITestConfigStorage {
    LevWstETHTestConfig[] internal testConfigs;

    constructor() {
         // SPARK
        testConfigs.push(
            LevWstETHTestConfig(
                address(0x12B54025C112Aa61fAce2CDB7118740875A566E9),
                address(0x2e7576042566f8D6990e07A1B61Ad1efd86Ae70d),
                address(0xC13e21B648A5Ee794902342038FF3aDAB66BE987),
                address(0xFc21d6d146E6086B8359705C8b28512a983db0cb),
                address(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE),
                1e15, 
                1e17,
                80e16,
                85e16
            ) // 0.1% slippage / 10% slippage cap  / 80% targetLTV - 85% maxLTV
        );

        // AAVE-v3
        testConfigs.push(
            LevWstETHTestConfig(
                address(0x0B925eD163218f6662a35e0f0371Ac234f9E9371),
                address(0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE),
                address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2),
                address(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3),
                address(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e),
                1e15, 
                1e17,
                80e16,
                85e16
            ) // 0.1% slippage / 10% slippage cap  / 80% targetLTV - 85% maxLTV
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(
            testConfigs[i].awstETH, 
            testConfigs[i].vdWETH, 
            testConfigs[i].lendingPool, 
            testConfigs[i].dataProvider, 
            testConfigs[i].poolAddressesProvider, 
            testConfigs[i].slippage, 
            testConfigs[i].slippageCap, 
            testConfigs[i].targetLTV, 
            testConfigs[i].maxLTV
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
