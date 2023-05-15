pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct AlpacaLendV2TestConfig {
    uint256 pid;
}

contract AlpacaLendV2TestConfigStorage is ITestConfigStorage {
    AlpacaLendV2TestConfig[] internal testConfigs;

    constructor() {
        // AlpacaLendV2 USDT - BSC
        testConfigs.push(AlpacaLendV2TestConfig(5));
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].pid);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
