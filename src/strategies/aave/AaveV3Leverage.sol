// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {BaseLeveragedStrategy} from "../../base/BaseLeveragedStrategy.sol";
import {AaveV3Adapter, IERC20, AdapterConfig, ProtocolConfig} from "../../adapter/aave/v3/AaveV3Adapter.sol";

contract AaveV3Leverage is AaveV3Adapter, BaseLeveragedStrategy {
    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external initializer {
        __AaveV3Adapter_init(_adapterConfig, _protocolConfig);
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        _deposit(amount, msg.sender);
        _onDeposit(amount, 10);
    }

    function withdraw(uint256 amount, address receiver) external override onlyVault {
        _withdraw(amount, receiver);
        _onWithdraw(10);
    }

    function _onDeposit(uint256 amount, uint256 leverage) internal {
        /*
         TODO
            1. borrow as much as leverage allows, or as close to it as possible
            2. take a flashloan to open more leverage
        */
        _enterLeveragedPosition(amount, leverage);
    }

    function _onWithdraw(uint256 leverage) internal {
        /*
         TODO
            1. repay flashloan
            2. repay borrowed amount
        */
        _exitLeveragedPosition(leverage);
    }

    function _enterLeveragedPosition(uint256 amount, uint256 leverage) internal override {
        for (uint256 i = 0; i < leverage; i++) {
            _borrow(_getAvailableBorrow(msg.sender) - LEVERAGED_BORROW_BUFFER);
            _depositUnderlying(_getUnderlyingBalance()); //supply to increase leverage
        }
    }

    function _exitLeveragedPosition(uint256 leverage) internal override {
        (, , , , uint256 ltv, ) = lendingPool.getUserAccountData(msg.sender);

        for (uint256 i = 0; i < leverage && _getTotalDebt(msg.sender) > 0; i++) {
            _withdrawUnderlying(((_getAvailableBorrow(msg.sender) * 1e4) / ltv) - LEVERAGED_BORROW_BUFFER);
            _repayBorrow(_getUnderlyingBalance());
        }
    }
}
