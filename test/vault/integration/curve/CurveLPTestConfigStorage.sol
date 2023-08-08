// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct CurveLPTestConfig {
    address asset;
    uint poolId;
}

contract CurveLPTestConfigStorage is ITestConfigStorage {
    CurveLPTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            CurveLPTestConfig(
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                0 // 3CRV pool
            )
        );
        testConfigs.push(
            CurveLPTestConfig(
                0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                0 // 3CRV pool
            )
        );
        testConfigs.push(
            CurveLPTestConfig(
                0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, // stEth
                24 // eCRV pool
            )
        );
        testConfigs.push(
            CurveLPTestConfig(
                0x3472A5A71965499acd81997a54BBA8D852C6E53d, // Badger
                92 // Badger / WBTC pool
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        CurveLPTestConfig memory config = testConfigs[i];
        return abi.encode(config.asset, config.poolId);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
