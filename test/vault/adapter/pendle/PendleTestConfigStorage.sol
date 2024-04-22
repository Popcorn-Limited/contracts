// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct PendleTestConfig {
    address asset;
    address pendleMarket;
    address pendleOracle;
    uint256 slippage;
    uint32 twapDuration;
    uint256 swapDelay;
    uint256 feeTier;
}

contract PendleTestConfigStorage is ITestConfigStorage {
    PendleTestConfig[] internal testConfigs;

    constructor() {
        // wstETH
        testConfigs.push(
            PendleTestConfig(
                0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, // wstETH
                0xD0354D4e7bCf345fB117cabe41aCaDb724eccCa2, // stETH 26DIC24,
                0x66a1096C6366b2529274dF4f5D8247827fe4CEA8, // pendle oracle
                1e14, 
                900,
                10 minutes,
                0.5e16
            )
        );

        // USDe
        testConfigs.push(
            PendleTestConfig(
                0x4c9EDD5852cd905f086C759E8383e09bff1E68B3, // USDe
                // 0xb4460e76D99eCaD95030204D3C25fb33C4833997, // USDe 4APR24
                0x19588F29f9402Bb508007FeADd415c875Ee3f19F, // USDe JUL24
                0x66a1096C6366b2529274dF4f5D8247827fe4CEA8,
                5e15, 
                900,
                10 minutes,
                1e16
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(
            testConfigs[i].asset, 
            testConfigs[i].pendleMarket, 
            testConfigs[i].pendleOracle, 
            testConfigs[i].slippage, 
            testConfigs[i].twapDuration,
            testConfigs[i].swapDelay,
            testConfigs[i].feeTier
        );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
