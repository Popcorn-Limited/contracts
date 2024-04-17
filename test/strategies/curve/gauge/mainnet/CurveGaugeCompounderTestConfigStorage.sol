// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../../abstract/ITestConfigStorage.sol";

struct CurveGaugeCompounderTestConfig {
    address asset;
    address gauge;
    address pool;
}

contract CurveGaugeCompounderTestConfigStorage is ITestConfigStorage {
    CurveGaugeCompounderTestConfig[] internal testConfigs;

    constructor() {
        // MAINNET - weETH / WETH
        testConfigs.push(
            CurveGaugeCompounderTestConfig(
                0x625E92624Bc2D88619ACCc1788365A69767f6200,
                0xf69Fb60B79E463384b40dbFDFB633AB5a863C9A2,
                0x625E92624Bc2D88619ACCc1788365A69767f6200
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].gauge, testConfigs[i].pool);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
