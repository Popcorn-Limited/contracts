// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct IporProtocolTestConfig {
    address _ammPoolsLens;
    address _ammPoolService;
    address _asset;
}

contract IporProtocolTestConfigStorage is ITestConfigStorage {
    IporProtocolTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            IporProtocolTestConfig(
                0x9bcde34F504A1a9BC3496Ba9f1AEA4c5FC400517,
                0xb653ED2bBd28DF9dde734FBe85f9312151940D01,
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 //USDC
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
            testConfigs[i]._ammPoolService,
            testConfigs[i]._ammPoolsLens,
            testConfigs[i]._asset
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
