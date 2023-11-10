// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AlpacaLendV1Adapter, IERC20, AdapterConfig} from "./AlpacaLendV1Adapter.sol";

contract AlpacaLendV1Depositor is AlpacaLendV1Adapter {
    function initialize(
        AdapterConfig memory _adapterConfig
    ) external initializer {
        __AlpacaLendV1Adapter_init(_adapterConfig);
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount, msg.sender);
    }

    function withdraw(uint256 amount, address receiver) external override onlyVault {
        _withdraw(amount, receiver);
    }
}
