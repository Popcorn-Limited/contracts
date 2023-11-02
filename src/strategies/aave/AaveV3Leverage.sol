// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {ILido, IWETH } from"../../adapter/lido/ILido.sol";
import {BaseLeveragedStrategy} from "../../base/BaseLeveragedStrategy.sol";
import {AaveV3Adapter, IERC20, AdapterConfig, ProtocolConfig} from "../../adapter/aave/v3/AaveV3Adapter.sol";

contract AaveV3Leverage is AaveV3Adapter, BaseLeveragedStrategy {
    /// @notice The booster address for Convex
    ILido public lido;

    // address public immutable weth;
    IWETH public weth;

    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) external initializer {
        __AaveV3Adapter_init(_adapterConfig, _protocolConfig);
        weth = IWETH(address(0));
        lido = ILido(address(0));
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
        //loop for entering leverage
        for (uint256 i = 0; i < leverage; i++) {
            _borrow(_getAvailableBorrow(msg.sender) - LEVERAGED_BORROW_BUFFER);
            _depositUnderlying(_getUnderlyingBalance()); //supply to increase leverage
        }
        //take a flash loan to enter a leverage and enter a position
        _getFlashLoan(amount, leverage);
    }

    function _exitLeveragedPosition(uint256 leverage) internal override {
        (, , , , uint256 ltv, ) = lendingPool.getUserAccountData(msg.sender);

        for (uint256 i = 0; i < leverage && _getTotalDebt(msg.sender) > 0; i++) {
            _withdrawUnderlying(((_getAvailableBorrow(msg.sender) * 1e4) / ltv) - LEVERAGED_BORROW_BUFFER);
            _repayBorrow(_getUnderlyingBalance());
        }

        _closeLongPosition();
    }

    function _openLongPosition(uint256 amount, uint256 leverage) internal {
        weth.withdraw(amount);
        uint256 stETHAmount = lido.submit{value: amount}(FEE_RECIPIENT);
        _depositUnderlying(stETHAmount);
        //withdraw eth to repay to flash loan
    }

    function _closeLongPosition() internal {
        (uint256 totalCollateralBase, , , , , ) = lendingPool.getUserAccountData(msg.sender);
        _withdrawUnderlying(totalCollateralBase);
    }

    function _getFlashLoan(uint256 amount, uint256 leverage) internal {
        uint256 flashLoanAmount = amount * leverage;

        bytes memory params = abi.encode(
            flashLoanAmount,
            leverage
        );

        address[] memory assets = new address[](1);
        assets[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); //WETH

        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint[] memory modes = new uint[](1);
        modes[0] = 0;

        lendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            params,
            0
        );
    }

    function executeOperation(
        address[] calldata assets,
        uint[] calldata amounts,
        uint[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        //open long position
        (, uint256 leverage) = abi.decode(params, (uint256, uint256));
        _openLongPosition(amounts[0] , leverage);

        // repay flashloan to Aave
        IERC20(assets[0]).approve(address(lendingPool), amounts[0] + premiums[0]);

        // Calculate discrepancy of debt vs current balance
        // @dev if there is a balance in this contract, it will be sent to msg.sender.
        // @dev if this underflows it means it wasn't a profitable trade
        uint leftOver = IERC20(assets[0]).balanceOf(address(this)) -
            (amounts[0] + premiums[0]);

        IERC20(assets[0]).transfer(msg.sender, leftOver);

        return true;
    }
}
