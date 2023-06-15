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
        // Polygon - USDC/WETH
        testConfigs.push(
            IchiTestConfig(
                16,
                0xA5cE107711789b350e04063D4EffBe6aB6eB05a4,
                0x0768A75F616B98ee0937673bD83B7aBF142236Ea,
                0xE592427A0AEce92De3Edee1F18E0157C05861564,
                500
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
