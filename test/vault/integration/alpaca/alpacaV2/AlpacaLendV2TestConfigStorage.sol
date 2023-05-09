pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct AlpacaLendV2TestConfig {
    address manager;
    uint256 pid;
}

contract AlpacaLendV2TestConfigStorage is ITestConfigStorage {
    AlpacaLendV2TestConfig[] internal testConfigs;

    constructor() {
        // AlpacaLendV2 USDT - BSC
        testConfigs.push(
            AlpacaLendV2TestConfig(
                0xD20B887654dB8dC476007bdca83d22Fa51e93407,
                5
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].manager, testConfigs[i].pid);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
