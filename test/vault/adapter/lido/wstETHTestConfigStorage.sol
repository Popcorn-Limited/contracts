// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LevWstETHTestConfig {
    address poolAddressesProvider;
    uint256 slippage;
    uint256 slippageCap;
    uint256 targetLTV;
    uint256 maxLTV;
}

contract LevWstETHTestConfigStorage is ITestConfigStorage {
    LevWstETHTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            LevWstETHTestConfig(
                address(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE),
                1e15, 
                1e17,
                80e16,
                85e16
            ) // 0.1% slippage / 10% slippage cap  / 80% targetLTV - 85% maxLTV
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(
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
