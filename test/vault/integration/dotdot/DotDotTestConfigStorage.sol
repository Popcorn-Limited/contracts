// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct DotDotTestConfig {
    address asset;
}

contract DotDotTestConfigStorage is ITestConfigStorage {
    DotDotTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            DotDotTestConfig(0x5b5bD8913D766D005859CE002533D4838B0Ebbb5)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
