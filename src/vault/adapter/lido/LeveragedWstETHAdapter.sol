// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {IwstETH} from "./IwstETH.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IWETH} from "../../../interfaces/external/IWETH.sol";
import {ICurveMetapool} from "../../../interfaces/external/curve/ICurveMetapool.sol";
import {ILendingPool, IAaveIncentives, IAToken, IFlashLoanReceiver, IProtocolDataProvider, DataTypes, IPoolAddressesProvider} from "../aave/aaveV3/IAaveV3.sol";

/// @title Leveraged wstETH yield adapter
/// @author Andrea Di Nenno
/// @notice ERC4626 wrapper for leveraging stETH yield 
/// @dev The strategy takes wstETH and deposits it into a lending protocol (aave). 
/// Then it borrows ETH, swap for wstETH and redeposits it
contract LeveragedWstETHAdapter is AdapterBase, IFlashLoanReceiver {
    // using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // address of the aave/spark router
    ILendingPool public lendingPool;
    IPoolAddressesProvider public poolAddressesProvider; 

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
    error DifferentAssets(address asset, address underlying);

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
        address aaveDataProvider,
        bytes memory _initData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        (address _wETH, address _stETH, address _poolAddressesProvider, uint256 _slippage, uint256 _targetLTV) = abi.decode(
            _initData,
            (address, address, address, uint256, uint256)
        );

        address baseAsset = asset();

        targetLTV = _targetLTV;
        slippage = _slippage;
        weth = IWETH(_wETH);
        firsDeposit = true;

        // retrieve and set wstETH aToken, lending pool
        (address _aToken, ,) = IProtocolDataProvider(aaveDataProvider)
            .getReserveTokensAddresses(baseAsset);
        
        if (IAToken(_aToken).UNDERLYING_ASSET_ADDRESS() != baseAsset)
            revert DifferentAssets(IAToken(_aToken).UNDERLYING_ASSET_ADDRESS(), baseAsset);

        interestToken = IERC20(_aToken);
        lendingPool = ILendingPool(IAToken(_aToken).POOL());
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);

        // retrieve and set WETH variable debt token
        (, , address _variableDebtToken) = IProtocolDataProvider(aaveDataProvider)
            .getReserveTokensAddresses(_wETH);
        debtToken = IERC20(_variableDebtToken); // variable debt WETH token

        _name = string.concat(
            "VaultCraft Leveraged ",
            IERC20Metadata(baseAsset).name(),
            " Adapter"
        );
        _symbol = string.concat(
            "vc-",
            IERC20Metadata(baseAsset).symbol()
        );

        // approve aave router to pull wstETH
        IERC20(baseAsset).approve(address(lendingPool), type(uint256).max);
        
        // approve aave pool to pull WETH as part of a flash loan
        IERC20(address(weth)).approve(address(lendingPool), type(uint256).max);

        // approve curve router to pull stETH for swapping
        IERC20(address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)).approve(address(StableSwapSTETH), type(uint256).max);
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

            // flash loan eth to repay part of the debt
            _flashLoanETH(amount, 0, 0);
        } else {
            // require that the update doesn't get the vault above target leverage
            require((currentDebt + amount).mulDiv(1e18, (currentCollateral + amount), Math.Rounding.Ceil) < targetLTV, 'Too much');

            // flash loan WETH from lending protocol and add to cdp
            _flashLoanETH(amount, 0, 2);
        }
    }


    /*//////////////////////////////////////////////////////////////
                          FLASH LOAN LOGIC
    //////////////////////////////////////////////////////////////*/

    // this is triggered after the flash loan is given, ie contract has loaned assets
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        (bool isWithdraw, uint256 assetsToWithdraw) = abi.decode(params, (bool, uint256 ));

        if(!isWithdraw) {
            // flash loan is to leverage UP 
            _increaseLeverage(amounts[0]);
        } else {
            // flash loan is to repay ETH debt as part of a withdrawal
            uint256 flashLoanDebt = amounts[0] + premiums[0];

            // repay cdp WETH debt 
            _repayDebt(amounts[0]);

            // withdraw collateral, swap repay flashloan 
            _reduceLeverage(assetsToWithdraw, flashLoanDebt);
        }
        
        return true;
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return poolAddressesProvider;
    }

    function POOL() external view returns (ILendingPool) {
        return lendingPool;
    }


    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit wstETH into lending protocol
    function _protocolDeposit(uint256 assets, uint256) internal override {    
        // deposit wstETH into aave - receive aToken here        
        _depositwstETH(asset(), assets);
    }

    /// @notice repay part of the vault debt and withdraw wstETH
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override {
        (, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV();
       
        // repay a portion of debt proportional to collateral to withdraw
        uint256 debtToRepay = assets.mulDiv(currentDebt, currentCollateral, Math.Rounding.Ceil);
        
        // flash loan debtToRepay - mode 0 - flash loan is repaid at the end
        _flashLoanETH(debtToRepay, assets, 0);
    }

    // increase leverage by borrowing ETH and depositing wstETH
    function _increaseLeverage(uint256 borrowAmount) internal {
        address wstETH = asset();

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
    function _reduceLeverage(uint256 toWithdraw, uint256 flashLoanDebt) internal {
        address asset = asset();

        // get flash loan amount of wstETH 
        uint256 flashLoanWstETHAmount = IwstETH(asset).getWstETHByStETH(flashLoanDebt);

        // apply slippage 
        uint256 wstETHBuffer = flashLoanWstETHAmount.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

        // withdraw wstETH from aave
        lendingPool.withdraw(asset, flashLoanWstETHAmount + wstETHBuffer + toWithdraw, address(this));

        // unwrap wstETH into stETH
        uint256 stETHAmount = IwstETH(asset).unwrap(flashLoanWstETHAmount + wstETHBuffer);
        
        // swap stETH for ETH and deposit into WETH - will be pulled by AAVE pool as flash loan repayment
        _swapToWETH(stETHAmount, flashLoanDebt);
    }

    // returns current loan to value, debt and collateral (token) amounts
    function _getCurrentLTV() internal view returns (uint256 loanToValue, uint256 debt, uint256 collateral) {
        debt = debtToken.balanceOf(address(this)); // ETH DEBT 
        collateral = IwstETH(asset()).getStETHByWstETH(interestToken.balanceOf(address(this))); // converted into ETH (stETH) amount;

        (debt == 0 || collateral == 0) ? loanToValue = 0 : loanToValue = debt.mulDiv(1e18, collateral, Math.Rounding.Ceil);
    }

    // deposit wstETH into lending protocol
    function _depositwstETH(address asset, uint256 amount) internal {
        lendingPool.supply(asset, amount, address(this), 0);

        if(firsDeposit) {
            // enable wstETH as collateral 
            lendingPool.setUserUseReserveAsCollateral(asset, true);
            firsDeposit = false;
        }
    }

    // borrow WETH from lending protocol
    // interestRateMode = 2 -> flash loan eth and deposit into cdp, don't repay
    // interestRateMode = 0 -> flash loan eth to repay cdp, have to repay flash loan at the end
    function _flashLoanETH(uint256 amount, uint256 assetsToWithdraw, uint256 interestRateMode) internal {
        // lendingPool.borrow(address(weth), amount, 2, 0, address(this));
        address[] memory assets = new address[](1);
        assets[0] = address(weth);
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = interestRateMode;
        
        bool isWithdraw = interestRateMode == 0 ? true : false; 
   
        lendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            interestRateModes,
            address(this),
            abi.encode(isWithdraw, assetsToWithdraw),
            0
        );
    }   
             
    // repay WETH debt 
    function _repayDebt(uint256 amount) internal {
        lendingPool.repay(address(weth), amount, 2, address(this));
    }

    // swaps stETH to WETH 
    function _swapToWETH(uint256 amount, uint256 minAmount) internal returns (uint256 amountWETHReceived) {
        amountWETHReceived = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            amount,
            minAmount
        );
        weth.deposit{value: amountWETHReceived}(); // get wrapped eth back
    }
}
