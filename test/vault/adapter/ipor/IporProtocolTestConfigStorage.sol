// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct IporProtocolTestConfig {
    address _ammPoolsLens;
    address _ammPoolService;
}

contract IporProtocolTestConfigStorage is ITestConfigStorage {
    IporProtocolTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            IporProtocolTestConfig(
                0x9bcde34F504A1a9BC3496Ba9f1AEA4c5FC400517,
                0xb653ED2bBd28DF9dde734FBe85f9312151940D01
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
            testConfigs[i]._ammPoolService,
            testConfigs[i]._ammPoolsLens
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
