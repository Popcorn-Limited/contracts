// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AaveV3Adapter, IERC20, AdapterConfig} from "../../adapter/aave/v3/AaveV3Adapter.sol";

contract AaveV3Depositor is AaveV3Adapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __AaveV3Adapter_init(_adapterConfig);
    }
}
