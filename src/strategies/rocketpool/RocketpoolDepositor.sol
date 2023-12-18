// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterConfig, RocketpoolAdapter} from "../../adapter/rocketpool/RocketpoolAdapter.sol";

contract RocketpoolDepositor is RocketpoolAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __RocketpoolAdapter_init(_adapterConfig);
    }
}
