// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import "../abstract/ITestConfigStorage.sol";

struct GmxTestConfig {
    address router;
}

contract GmxTestConfigStorage is ITestConfigStorage{
    GmxTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            GmxTestConfig(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].router);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
