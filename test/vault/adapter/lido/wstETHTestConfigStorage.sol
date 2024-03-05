// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LevWstETHTestConfig {
    address weth;
    address stETH;
    address poolAddressesProvider;
    uint256 slippage;
    uint256 targetLTV;
}

contract LevWstETHTestConfigStorage is ITestConfigStorage {
    LevWstETHTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            LevWstETHTestConfig(
                address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
                address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84),
                address(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE),
                1e15, 
                5e17
            ) // 10 BPS / 50% LTV
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].weth, testConfigs[i].stETH, testConfigs[i].poolAddressesProvider, testConfigs[i].slippage, testConfigs[i].targetLTV);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
