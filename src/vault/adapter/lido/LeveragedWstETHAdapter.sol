// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {IwstETH} from "./IwstETH.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IWETH} from "../../../interfaces/external/IWETH.sol";
import {ICurveMetapool} from "../../../interfaces/external/curve/ICurveMetapool.sol";
import {ILendingPool, IAaveIncentives, IAToken, IProtocolDataProvider, DataTypes} from "../aave/aaveV3/IAaveV3.sol";

/// @title Leveraged wstETH yield adapter
/// @author Andrea Di Nenno
/// @notice ERC4626 wrapper for leveraging stETH yield 
/// @dev The strategy takes ETH and deposits it into a lending protocol (aave). 
/// Then it borrows ETH, swap for wstETH and redeposits it
contract LeveragedWstETHAdapter is AdapterBase {
    // using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // address of the aave/spark router
    ILendingPool public lendingPoolRouter;

    IERC20 public debtToken; // aave eth debt token
    IERC20 public interestToken; // aave awstETH

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage
    IWETH public weth;

    uint256 public targetLTV; // in 18 decimals - 1e17 being 0.1%
    bool firsDeposit; 

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
  //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Lido Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param _initData Encoded data for the Lido adapter initialization.
     * @dev `_slippage` - allowed slippage in 1e18
     * @dev `_weth` - Weth address.
     * @dev `_targetLTV` - The desired loan to value of the vault CDP.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address _lendingPoolRouter,
        bytes memory _initData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        (address _wETH, address _vdWETH, uint256 _slippage, uint256 _targetLTV) = abi.decode(
            _initData,
            (address, address, uint256, uint256)
        );

        targetLTV = _targetLTV;
        slippage = _slippage;
        lendingPoolRouter = ILendingPool(_lendingPoolRouter);
        weth = IWETH(_wETH);
        firsDeposit = true;

        // retrieve asset relative debt token and interest token
        address baseAsset = asset();
        DataTypes.ReserveData2 memory poolData = lendingPoolRouter.getReserveData(baseAsset);
        interestToken = IERC20(poolData.aTokenAddress);
        debtToken = IERC20(_vdWETH); // variable debt WETH token

        _name = string.concat(
            "VaultCraft Leveraged wstETH ",
            IERC20Metadata(address(weth)).name(),
            " Adapter"
        );
        _symbol = string.concat(
            "vcwstETH-",
            IERC20Metadata(address(weth)).symbol()
        );

        // approve aave router to pull wstETH
        IERC20(baseAsset).approve(address(lendingPoolRouter), type(uint256).max);
    }

    receive() external payable {}

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
    }

    function getLTV() public view returns (uint256 ltv) {
        (ltv,,) = _getCurrentLTV();
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256 total) {
        (, uint256 debt, uint256 collateral) = _getCurrentLTV();
        debt >= collateral ? total = 0 : total = collateral - debt;
    }

    // TODO 
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        // uint256 supply = totalSupply();
        // return
        //     supply == 0
        //         ? shares
        //         : shares.mulDiv(
        //             lido.balanceOf(address(this)),
        //             supply,
        //              Math.Rounding.Ceil
        //         );
    }

    // amount of WETH to borrow OR amount of WETH to repay (converted into wstETH amount internally)
    function adjustLeverage(uint256 amount) external onlyOwner {
        // get vault current leverage : debt/collateral
        (uint256 currentLTV, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV();

        // de-leverage if vault LTV is higher than target
        if (currentLTV > targetLTV) {
            // require that the update gets the vault LTV back below target leverage
            require((currentDebt - amount).mulDiv(1e18, (currentCollateral - amount), Math.Rounding.Ceil) < targetLTV, 'Too little');

            _reduceLeverage(amount);
        } else {
            // require that the update doesn't get the vault above target leverage
            require((currentDebt + amount).mulDiv(1e18, (currentCollateral + amount), Math.Rounding.Ceil) < targetLTV, 'Too much');

            _increaseLeverage(amount);
        }
    }


    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit wstETH into lending protocol
    function _protocolDeposit(uint256 assets, uint256) internal override {    
        // deposit wstETH into aave - receive aToken here        
        _depositwstETH(asset(), assets);
    }

    /// @notice Withdraw from LIDO pool
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override {
        // IF AMOUNT doesn't get vault above target LTV, withdraw directly 
        // else - repay debt and withdraw
        // repay wstETH 

        // withdraw wstETH
    }

    // increase leverage by borrowing ETH and depositing wstETH
    function _increaseLeverage(uint256 borrowAmount) internal {
        address wstETH = asset();

        // borrow WETH from lending protocol
        _borrowETH(borrowAmount);

        // unwrap into ETH 
        weth.withdraw(borrowAmount);

        // get amount of wstETH the vault receives 
        uint256 wstETHAmount = IwstETH(wstETH).getWstETHByStETH(borrowAmount);

        // stake borrowed eth and receive wstETH
        (bool sent, ) =  wstETH.call{value: borrowAmount}('');
        require(sent, 'Fail to send eth to wstETH');

        // deposit wstETH into lending protocol
        _depositwstETH(wstETH, wstETHAmount);
    }

    // reduce leverage by withdrawing wstETH, swapping to ETH repaying ETH debt
    // repayAmount is a ETH (wETH) amount
    function _reduceLeverage(uint256 repayAmount) internal {
        address asset = asset();

        // get amount of wstETH
        uint256 amountWstETH = IwstETH(asset).getWstETHByStETH(repayAmount);

        // withdraw wstETH from aave
        lendingPoolRouter.withdraw(asset, amountWstETH, address(this));

        // unwrap wstETH into stETH
        uint256 stETHAmount = IwstETH(asset).unwrap(amountWstETH);
        
        // swap stETH for ETH and deposit into WETH
        uint256 WETHAmount = _swapToWETH(stETHAmount);

        // assert.equal(WETHAmount, repayAmount) ? TODO

        // repay WETH debt 
        _repayDebt(WETHAmount);
    }

    // returns current loan to value, debt and collateral (token) amounts
    function _getCurrentLTV() internal view returns (uint256 loanToValue, uint256 debt, uint256 collateral) {
        debt = debtToken.balanceOf(address(this)); // ETH DEBT 
        collateral = IwstETH(asset()).getStETHByWstETH(interestToken.balanceOf(address(this))); // converted into ETH (stETH) amount;

        (debt == 0 || collateral == 0) ? loanToValue = 0 : loanToValue = debt.mulDiv(1e18, collateral, Math.Rounding.Ceil);
    }

    // deposit wstETH into lending protocol
    function _depositwstETH(address asset, uint256 amount) internal {
        lendingPoolRouter.supply(asset, amount, address(this), 0);

        if(firsDeposit) {
            // enable wstETH as collateral 
            lendingPoolRouter.setUserUseReserveAsCollateral(asset, true);
            firsDeposit = false;
        }
    }

    // borrow WETH from lending protocol
    function _borrowETH(uint256 amount) internal {
        lendingPoolRouter.borrow(address(weth), amount, 2, 0, address(this));
    }
             
    // repay WETH debt 
    function _repayDebt(uint256 amount) internal {
        lendingPoolRouter.repay(address(weth), amount, 2, address(this));
    }

    // swaps stETH to WETH 
    function _swapToWETH(uint256 amount) internal returns (uint256 amountWETHReceived) {
        amountWETHReceived = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            amount,
            0
        );
        weth.deposit{value: amountWETHReceived}(); // get wrapped eth back
    }
}
