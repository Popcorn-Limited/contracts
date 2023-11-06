// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {CompoundV2Adapter, IERC20, AdapterConfig} from "../../adapter/compound/v2/CompoundV2Adapter.sol";

contract CompoundV2Depositor is CompoundV2Adapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __CompoundV2Adapter_init(_adapterConfig);
    }
}
