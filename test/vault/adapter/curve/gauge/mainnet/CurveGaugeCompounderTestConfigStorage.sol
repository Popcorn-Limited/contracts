// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../../abstract/ITestConfigStorage.sol";

struct CurveGaugeCompounderTestConfig {
    address asset;
    address gauge;
}

contract CurveGaugeCompounderTestConfigStorage is ITestConfigStorage {
    CurveGaugeCompounderTestConfig[] internal testConfigs;

    constructor() {
        // MAINNET - weETH / WETH
        testConfigs.push(
            CurveGaugeCompounderTestConfig(
                0x13947303F63b363876868D070F14dc865C36463b,
                0x1CAC1a0Ed47E2e0A313c712b2dcF85994021a365
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].gauge);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
