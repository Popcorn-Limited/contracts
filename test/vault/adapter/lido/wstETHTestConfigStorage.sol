// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LevWstETHTestConfig {
    address weth;
    address variableDebtWeth;
    uint256 slippage;
    uint256 targetLTV;
}

contract LevWstETHTestConfigStorage is ITestConfigStorage {
    LevWstETHTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            LevWstETHTestConfig(
                address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), 
                address(0x2e7576042566f8D6990e07A1B61Ad1efd86Ae70d), 
                1, 
                5e17
            ) // 10 BPS / 50% LTV
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].weth, testConfigs[i].variableDebtWeth, testConfigs[i].slippage, testConfigs[i].targetLTV);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
