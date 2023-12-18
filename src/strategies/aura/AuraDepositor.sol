// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AuraAdapter, IERC20, AdapterConfig} from "../../adapter/aura/AuraAdapter.sol";

contract AuraDepositor is AuraAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __AuraAdapter_init(_adapterConfig);
    }
}
