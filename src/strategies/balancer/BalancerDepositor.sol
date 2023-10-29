// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {
    BalancerGaugeAdapter, IERC20, AdapterConfig
} from "../../adapter/balancer/BalancerGaugeAdapter.sol";

contract BalanceDepositor is BalancerGaugeAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __BalanceGaugeAdapter_init(_adapterConfig);
    }
}
