// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LidoTestConfig {
    address pool;
    uint256 wEthId;
    uint256 stEthId;
    uint256 slippage;
}

contract LidoTestConfigStorage is ITestConfigStorage {
    LidoTestConfig[] internal testConfigs;

    constructor() {
        // WETH
        testConfigs.push(
            LidoTestConfig(
                0xDC24316b9AE028F1497c275EB9192a3Ea0f67022,
                0,
                1,
                100
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].pool,
                testConfigs[i].wEthId,
                testConfigs[i].stEthId,
                testConfigs[i].slippage
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
