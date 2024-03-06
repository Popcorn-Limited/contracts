pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct AuraCompounderTestConfig {
    uint256 pid;
    address balVault;
    bytes32 balPoolId;
    address[] underlyings;
}

contract AuraCompounderTestConfigStorage is ITestConfigStorage {
    AuraCompounderTestConfig[] internal testConfigs;

    constructor() {
        address[] memory underlyings = new address[](3);
        underlyings[0] = 0x6733F0283711F225A447e759D859a70b0c0Fd2bC;
        underlyings[1] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        underlyings[2] = 0xdEdb11A6a23263469567C2881A9b9F8629eE0041;
        testConfigs.push(
            AuraCompounderTestConfig(
                196,
                0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                0xdedb11a6a23263469567c2881a9b9f8629ee0041000000000000000000000669,
                underlyings
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].pid,
                testConfigs[i].balVault,
                testConfigs[i].balPoolId,
                testConfigs[i].underlyings
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
