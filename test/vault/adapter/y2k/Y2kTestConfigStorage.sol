// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ITestConfigStorage} from "../abstract/ITestConfigStorage.sol";

struct Y2kTestConfig {
    address carouselFactory;
    uint256 marketId;
}

contract Y2kTestConfigStorage is ITestConfigStorage {
    Y2kTestConfig[] internal testConfigs;

    constructor() {
        testConfigs.push(
            //y2kMIM_950_WETH*
            Y2kTestConfig(
                0xC3179AC01b7D68aeD4f27a19510ffe2bfb78Ab3e,
                9242501961483910761021487408535674013343791205950741336512202491204017755343
            )
        );
    }

    function getTestConfig(uint256 i) public view returns (bytes memory) {
        return abi.encode(testConfigs[i].carouselFactory, testConfigs[i].marketId);
    }

    function getTestConfigLength() public view returns (uint256) {
        return testConfigs.length;
    }
}
