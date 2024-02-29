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
        underlyings[0] = 0x596192bB6e41802428Ac943D2f1476C1Af25CC0E;
        underlyings[1] = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
        underlyings[2] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        testConfigs.push(
            AuraCompounderTestConfig(
                189,
                0xBA12222222228d8Ba445958a75a0704d566BF2C8,
                0x596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659,
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
