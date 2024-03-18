// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LevWstETHTestConfig {
    address poolAddressesProvider;
    uint256 slippage;
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
                5e17,
                6e17
            ) // 10 BPS / 50% targetLTV - 60% maxLTV
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].poolAddressesProvider, testConfigs[i].slippage, testConfigs[i].targetLTV, testConfigs[i].maxLTV);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
