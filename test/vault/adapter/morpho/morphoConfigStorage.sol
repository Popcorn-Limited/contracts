pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct LevWstETHTestConfig {
    bytes32 marketId;
    uint256 slippage;
    uint256 targetLTV;
    uint256 maxLTV;
}

contract MorphoLevWstETHTestConfigStorage is ITestConfigStorage {
    LevWstETHTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            LevWstETHTestConfig(
                hex"c54d7acf14de29e0e5527cabd7a576506870346a78a11a6762e2cca66322ec41",
                1e15, 
                5e17,
                6e17
            ) // 10 BPS / 50% targetLTV - 60% maxLTV
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].marketId, testConfigs[i].slippage, testConfigs[i].targetLTV, testConfigs[i].maxLTV);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
