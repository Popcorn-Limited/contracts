// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../../abstract/ITestConfigStorage.sol";

struct CurveChildGaugeTestConfig {
    address asset;
    address crv;
}

contract CurveChildGaugeTestConfigStorage is ITestConfigStorage {
    CurveChildGaugeTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            CurveChildGaugeTestConfig(
                0xa138341185a9D0429B0021A11FB717B225e13e1F,
                0x172370d5Cd63279eFa6d502DAB29171933a610AF
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].crv);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
