pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct AlpacaLendV1TestConfig {
    address alpacaVault;
}

contract AlpacaLendV1TestConfigStorage is ITestConfigStorage {
    AlpacaLendV1TestConfig[] internal testConfigs;

    constructor() {
        // AlpacaLendV1 USDT - BSC
        testConfigs.push(
            AlpacaLendV1TestConfig(0x158Da805682BdC8ee32d52833aD41E74bb951E59)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].alpacaVault);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
