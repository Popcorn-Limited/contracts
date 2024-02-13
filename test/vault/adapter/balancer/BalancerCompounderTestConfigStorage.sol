pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct BalancerCompounderTestConfig {
    address gauge;
    address balVault;
}

contract BalancerCompounderTestConfigStorage is ITestConfigStorage {
    BalancerCompounderTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            BalancerCompounderTestConfig(
                0xee01c0d9c0439c94D314a6ecAE0490989750746C,
                0xBA12222222228d8Ba445958a75a0704d566BF2C8
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].gauge, testConfigs[i].balVault);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
