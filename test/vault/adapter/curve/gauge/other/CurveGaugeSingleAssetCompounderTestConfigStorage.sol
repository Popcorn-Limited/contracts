// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../../../abstract/ITestConfigStorage.sol";

struct CurveGaugeSingleAssetCompounderTestConfig {
    address asset;
    address lpToken;
    address gauge;
    int128 indexIn;
}

contract CurveGaugeSingleAssetCompounderTestConfigStorage is ITestConfigStorage {
    CurveGaugeSingleAssetCompounderTestConfig[] internal testConfigs;

    constructor() {
        // ARBITRUM - Frax - crvUSD/Frax
        testConfigs.push(
            CurveGaugeSingleAssetCompounderTestConfig(
                0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F,
                0x2FE7AE43591E534C256A1594D326e5779E302Ff4,
                0x059E0db6BF882f5fe680dc5409C7adeB99753736,
                int128(1)
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].asset, testConfigs[i].lpToken, testConfigs[i].gauge, testConfigs[i].indexIn);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
