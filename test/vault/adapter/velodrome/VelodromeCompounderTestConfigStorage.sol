// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct VelodromeCompounderTestConfig {
    address gauge;
    address solidlyRouter;
}

contract VelodromeCompounderTestConfigStorage is ITestConfigStorage {
    VelodromeCompounderTestConfig[] internal testConfigs;

    constructor() {
        // Optimism - KUJI-​VELO vLP V2
        testConfigs.push(
            VelodromeCompounderTestConfig(0x60861f228AF12461a6D42C970b3eFF5648504b13, 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gauge, testConfigs[i].solidlyRouter);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
