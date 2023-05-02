pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../abstract/ITestConfigStorage.sol";

struct AlpacaLendV1TestConfig {
    address alpacaVault;
}

contract AlpacaLendV1TestConfigStorage is ITestConfigStorage {
    AlpacaLendV1TestConfig[] internal testConfigs;

    constructor() {
        // AlpacaLendV1 BNB - BSC
        testConfigs.push(
            AlpacaLendV1TestConfig(0xd7D069493685A581d27824Fc46EdA46B7EfC0063)
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].alpacaVault);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
