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
        // MAINNET - weeTH / rswETH
        testConfigs.push(
            CurveGaugeCompounderTestConfig(
                0x278cfB6f06B1EFc09d34fC7127d6060C61d629Db,
                0x0Bfb387B87e8Bf173a10A7DCf786B0b7875F6771
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
