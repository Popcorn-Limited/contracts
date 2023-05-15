// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../../abstract/ITestConfigStorage.sol";

struct CurveGaugeTestConfig {
    uint256 gaugeId;
}

contract CurveGaugeTestConfigStorage is ITestConfigStorage {
    CurveGaugeTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(CurveGaugeTestConfig(141));
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gaugeId);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
