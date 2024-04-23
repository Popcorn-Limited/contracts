// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct PendleTestConfig {
    address asset;
    address pendleMarket;
    address pendleRouterStatic;
    uint256 swapDelay;
}

contract PendleTestConfigStorage is ITestConfigStorage {
    PendleTestConfig[] internal testConfigs;

    constructor() {
        // wstETH
        testConfigs.push(
            PendleTestConfig(
                0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, // wstETH
                0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2, // stETH 26DIC24,
                0x263833d47eA3fA4a30f269323aba6a107f9eB14C, // router static
                10 minutes
            )
        );

        // USDe
        testConfigs.push(
            PendleTestConfig(
                0x4c9EDD5852cd905f086C759E8383e09bff1E68B3, // USDe
                // 0xb4460e76D99eCaD95030204D3C25fb33C4833997, // USDe 4APR24
                0x19588F29f9402Bb508007FeADd415c875Ee3f19F, // USDe JUL24
                0x263833d47eA3fA4a30f269323aba6a107f9eB14C, // router static
                10 minutes
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(
            testConfigs[i].asset, 
            testConfigs[i].pendleMarket, 
            testConfigs[i].pendleRouterStatic, 
            testConfigs[i].swapDelay
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
