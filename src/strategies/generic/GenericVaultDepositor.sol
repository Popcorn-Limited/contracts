// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {GenericVaultAdapter, IERC20, AdapterConfig} from "../../adapter/generic/GenericVaultAdapter.sol";

contract GenericVaultDepositor is GenericVaultAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __GenericVaultAdapter_init(_adapterConfig);
    }
}
