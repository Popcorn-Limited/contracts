// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct IchiTestConfig {
    uint256 pid;
    address depositGuard;
    address vaultDeployer;
    address uniRouter;
    uint256 swapFee;
}

contract IchiTestConfigStorage is ITestConfigStorage {
    IchiTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet - ichiwETH
        testConfigs.push(
            IchiTestConfig(
                25,
                0xe6e32D20258f475BaA8d0B39d4C391B96f0ef70A,
                0xfF7B5E167c9877f2b9f65D19d9c8c9aa651Fe19F,
                0xE592427A0AEce92De3Edee1F18E0157C05861564,
                100
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].pid,
                testConfigs[i].depositGuard,
                testConfigs[i].vaultDeployer,
                testConfigs[i].uniRouter,
                testConfigs[i].swapFee
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
