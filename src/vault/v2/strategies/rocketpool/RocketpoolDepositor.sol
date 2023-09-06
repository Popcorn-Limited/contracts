// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {
    IERC20,
    AdapterConfig,
    ProtocolConfig,
    RocketpoolAdapter
} from "../../adapter/rocketpool/RocketpoolAdapter.sol";

contract RocketpoolDepositor is RocketpoolAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external initializer {
        __RocketpoolAdapter_init(_adapterConfig, _protocolConfig);
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount);
    }

    function withdraw(uint256 amount, address receiver) external override onlyVault {
        _withdraw(amount, receiver);
    }
}
