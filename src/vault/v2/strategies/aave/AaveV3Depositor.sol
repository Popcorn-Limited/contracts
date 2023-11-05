// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AaveV3Adapter, IERC20, AdapterConfig, ProtocolConfig} from "../../adapter/aave/v3/AaveV3Adapter.sol";

contract AaveV3Depositor is AaveV3Adapter {
    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external initializer {
        __AaveV3Adapter_init(_adapterConfig, _protocolConfig);
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount);
    }

    function withdraw(uint256 amount) external override onlyVault {
        _withdraw(amount);
    }
}
