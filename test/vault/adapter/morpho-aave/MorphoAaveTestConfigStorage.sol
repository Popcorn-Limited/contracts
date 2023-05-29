// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct MorphoAaveTestConfig {
    address poolToken;
    address morpho;
    address lens;
}

contract MorphoAaveTestConfigStorage is ITestConfigStorage {
    MorphoAaveTestConfig[] internal testConfigs;

    constructor() {
        // Mainnet - Aave USD
        testConfigs.push(
            MorphoAaveTestConfig(
                0xBcca60bB61934080951369a648Fb03DF4F96263C,
                0x777777c9898D384F785Ee44Acfe945efDFf5f3E0,
                0x507fA343d0A90786d86C7cd885f5C49263A91FF4
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return
            abi.encode(
                testConfigs[i].poolToken,
                testConfigs[i].morpho,
                testConfigs[i].lens
            );
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
