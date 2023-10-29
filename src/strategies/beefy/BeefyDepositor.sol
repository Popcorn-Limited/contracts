// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BeefyAdapter, IERC20, AdapterConfig} from "../../adapter/beefy/BeefyAdapter.sol";

contract BeefyDepositor is BeefyAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __BeefyAdapter_init(_adapterConfig);
    }
}
