// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AuraAdapter, IERC20, AdapterConfig, ProtocolConfig} from "./AuraAdapter.sol";

contract AuraDepositor is AcrossAdapter {
    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external initializer {
        __AuraAdapter_init(_adapterConfig, _protocolConfig);
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount);
    }

    function withdraw(uint256 amount) external override onlyVault {
        _withdraw(amount);
    }
}
