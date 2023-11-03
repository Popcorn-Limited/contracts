// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IProtocolOracle} from "../../adapter/aave/v3/IAaveV3.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ILido, IWETH, ICurveMetapool} from"../../adapter/lido/ILido.sol";
import {BaseLeveragedStrategy} from "../../base/BaseLeveragedStrategy.sol";
import {AaveV3Adapter, IERC20, AdapterConfig, ProtocolConfig} from "../../adapter/aave/v3/AaveV3Adapter.sol";


contract AaveV3Leverage is AaveV3Adapter, BaseLeveragedStrategy {
    int128 private constant WETH_ID = 0;
    int128 private constant STETH_ID = 1;

    ILido public constant lido = ILido(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IWETH public constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);


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
        _enterLeveragedPosition(amount, leverage);
    }

    function _onWithdraw(uint256 leverage) internal {
        _exitLeveragedPosition(leverage);
    }

    function _enterLeveragedPosition(uint256 amount, uint256 leverage) internal override {
        uint256 leverageAmount = amount * leverage;
        uint256 loanToValueRatio = (leverageAmount - amount) / leverageAmount;

        //take a flash loan to enter a leverage and enter a position
        uint256 flashLoanAmount = loanToValueRatio * leverageAmount;
        _getFlashLoan(flashLoanAmount, leverage);
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
        StableSwapSTETH.exchange(
            STETH_ID,
            WETH_ID,
            amount,
            0
        );
    }

    function _closeLongPosition() internal {
        (uint256 totalCollateralBase, , , , , ) = lendingPool.getUserAccountData(msg.sender);
        _withdrawUnderlying(totalCollateralBase);
    }

    function _getFlashLoan(uint256 flashLoanAmount, uint256 leverage) internal {
        bytes memory params = abi.encode(
            flashLoanAmount,
            leverage
        );

        address[] memory assets = new address[](1);
        assets[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); //WETH

        uint[] memory amounts = new uint[](1);
        amounts[0] = flashLoanAmount;

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
    /*//////////////////////////////////////////////////////////////
                            BORROW LOGIC
    //////////////////////////////////////////////////////////////*/
    uint256 private constant USE_VARIABLE_DEBT = 2;

    function _borrow(uint256 amount) internal  {
        lendingPool.borrow(
            address(underlying),
            amount,
            USE_VARIABLE_DEBT,
            0,
            address(this)
        );
    }

    function _repayBorrow(uint256 amount) internal {
        lendingPool.repay(
            address(underlying),
            amount,
            USE_VARIABLE_DEBT,
            address(this)
        );
    }

    function _getAvailableBorrow(address user) internal view returns (uint256) {
        (, , uint256 availableBorrowsBase, , , ) = lendingPool.getUserAccountData(user);
        return (availableBorrowsBase * (10**ERC20(address(underlying)).decimals())) / _getAssetPrice();
    }

    function _getTotalDebt(address user) internal view returns (uint256) {
        (, uint256 totalDebtBase, , , , ) = lendingPool.getUserAccountData(user);
        return (totalDebtBase * (10**ERC20(address(underlying)).decimals())) / _getAssetPrice();
    }

    function _getAssetPrice() internal view returns (uint256) {
        return IProtocolOracle(
            poolAddressProvider.getPriceOracle()
        ).getAssetPrice(address(underlying));
    }

    function _getUnderlyingBalance() internal view returns(uint256) {
        return underlying.balanceOf(address(this));
    }
}
