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

    IWETH public weth;
    IERC20 public debtToken; // aave eth debt token
    IERC20 public interestToken; // aave awstETH

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;
    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage

    uint256 public targetLTV; // in 18 decimals - 1e17 being 0.1%
    uint256 public maxLTV; // max ltv the vault can reach

    error DifferentAssets(address asset, address underlying);

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Lido Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param _initData Encoded data for the adapter initialization.
     * @dev `_slippage` - allowed slippage in 1e18
     * @dev `_weth` - Weth address.
     * @dev `_stEth` - stETH address.
     * @dev `_poolAddressesProvider` - aave Pool Addresses Provider contract address.
     * @dev `_targetLTV` - The desired loan to value of the vault CDP.
     * @dev `_maxLTV` - The max loan to value allowed before a automatic de-leverage
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address aaveDataProvider,
        bytes memory _initData
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        (
            address _wETH,
            address _stETH,
            address _poolAddressesProvider,
            uint256 _slippage,
            uint256 _targetLTV,
            uint256 _maxLTV
        ) = abi.decode(
                _initData,
                (address, address, address, uint256, uint256, uint256)
            );

        address baseAsset = asset();

        targetLTV = _targetLTV;
        maxLTV = _maxLTV;

        slippage = _slippage;
        weth = IWETH(_wETH);

        // retrieve and set wstETH aToken, lending pool
        (address _aToken, , ) = IProtocolDataProvider(aaveDataProvider)
            .getReserveTokensAddresses(baseAsset);

        interestToken = IERC20(_aToken);
        lendingPool = ILendingPool(IAToken(_aToken).POOL());
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);

        // retrieve and set WETH variable debt token
        (, , address _variableDebtToken) = IProtocolDataProvider(
            aaveDataProvider
        ).getReserveTokensAddresses(_wETH);
        debtToken = IERC20(_variableDebtToken); // variable debt WETH token

        _name = string.concat(
            "VaultCraft Leveraged ",
            IERC20Metadata(baseAsset).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(baseAsset).symbol());

        // approve aave router to pull wstETH
        IERC20(baseAsset).approve(address(lendingPool), type(uint256).max);

        // approve aave pool to pull WETH as part of a flash loan
        IERC20(address(weth)).approve(address(lendingPool), type(uint256).max);

        // approve curve router to pull stETH for swapping
        IERC20(address(_stETH)).approve(
            address(StableSwapSTETH),
            type(uint256).max
        );
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

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {
        uint256 debt = IwstETH(asset()).getWstETHByStETH(
            debtToken.balanceOf(address(this))
        ); // wstETH DEBT
        uint256 collateral = interestToken.balanceOf(address(this)); // wstETH collateral

        if (debt >= collateral) {
            return 0;
        } else {
            uint256 total = collateral - debt;
            // if there's debt, apply slippage to repay it
            if (debt > 0) {
                uint256 slippageDebt = debt.mulDiv(
                    slippage,
                    1e18,
                    Math.Rounding.Ceil
                );
                total -= slippageDebt;
            }
            return total;
        }
    }

    function getLTV() public view returns (uint256 ltv) {
        (ltv, , ) = _getCurrentLTV();
    }

    /*//////////////////////////////////////////////////////////////
                          FLASH LOAN LOGIC
    //////////////////////////////////////////////////////////////*/

    function ADDRESSES_PROVIDER()
        external
        view
        returns (IPoolAddressesProvider)
    {
        return poolAddressesProvider;
    }

    function POOL() external view returns (ILendingPool) {
        return lendingPool;
    }

    // this is triggered after the flash loan is given, ie contract has loaned assets at this point
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        (bool isWithdraw, bool isFullWithdraw, uint256 assetsToWithdraw) = abi
            .decode(params, (bool, bool, uint256));

        if (isWithdraw) {
            // flash loan is to repay ETH debt as part of a withdrawal
            uint256 flashLoanDebt = amounts[0] + premiums[0];

            // repay cdp WETH debt
            lendingPool.repay(address(weth), amounts[0], 2, address(this));

            // withdraw collateral, swap, repay flashloan
            _reduceLeverage(isFullWithdraw, assetsToWithdraw, flashLoanDebt);
        } else {
            // flash loan is to leverage UP
            _redepositAsset(amounts[0]);
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit wstETH into lending protocol
    function _protocolDeposit(uint256 assets, uint256) internal override {
        // deposit wstETH into aave - receive aToken here
        lendingPool.supply(asset(), assets, address(this), 0);
    }

    /// @notice repay part of the vault debt and withdraw wstETH
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override {
        (, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV();
        uint256 ethAssetsValue = IwstETH(asset()).getStETHByWstETH(assets);

        bool isFullWithdraw = assets == _totalAssets();

        // get the LTV we would have without repaying debt
        uint256 futureLTV = isFullWithdraw
            ? type(uint256).max
            : currentDebt.mulDiv(
                1e18,
                (currentCollateral - ethAssetsValue),
                Math.Rounding.Floor
            );

        if (futureLTV <= maxLTV || currentDebt == 0) {
            // 1 - withdraw any asset amount with no debt
            // 2 - withdraw assets with debt but the change doesn't take LTV above max
            lendingPool.withdraw(asset(), assets, address(this));
        } else {
            // 1 - withdraw assets but repay debt
            uint256 debtToRepay = isFullWithdraw
                ? currentDebt
                : currentDebt -
                    (
                        targetLTV.mulDiv(
                            (currentCollateral - ethAssetsValue),
                            1e18,
                            Math.Rounding.Floor
                        )
                    );

            // flash loan debtToRepay - mode 0 - flash loan is repaid at the end
            _flashLoanETH(debtToRepay, assets, 0, isFullWithdraw);
        }
    }

    // increase leverage by borrowing ETH and depositing wstETH
    function _redepositAsset(uint256 borrowAmount) internal {
        address wstETH = asset();

        // account for eventual eth dust
        borrowAmount += address(this).balance;

        // unwrap into ETH
        weth.withdraw(borrowAmount);

        // get amount of wstETH the vault receives
        uint256 wstETHAmount = IwstETH(wstETH).getWstETHByStETH(borrowAmount);

        // stake borrowed eth and receive wstETH
        (bool sent, ) = wstETH.call{value: borrowAmount}("");
        require(sent, "Fail to send eth to wstETH");

        // deposit wstETH into lending protocol
        _protocolDeposit(wstETHAmount, 0);
    }

    // reduce leverage by withdrawing wstETH, swapping to ETH repaying ETH debt
    // repayAmount is a ETH (wETH) amount
    function _reduceLeverage(
        bool isFullWithdraw,
        uint256 toWithdraw,
        uint256 flashLoanDebt
    ) internal {
        address asset = asset();

        // get flash loan amount of wstETH
        uint256 flashLoanWstETHAmount = IwstETH(asset).getWstETHByStETH(
            flashLoanDebt
        );

        // get slippage buffer for swapping with flashLoanDebt as minAmountOut
        uint256 wstETHBuffer = IwstETH(asset).getWstETHByStETH(
            flashLoanDebt.mulDiv(slippage, 1e18, Math.Rounding.Floor)
        );

        // withdraw wstETH from aave
        if (isFullWithdraw) {
            // withdraw all
            lendingPool.withdraw(asset, type(uint256).max, address(this));
        } else {
            lendingPool.withdraw(
                asset,
                flashLoanWstETHAmount + wstETHBuffer + toWithdraw,
                address(this)
            );
        }

        // unwrap wstETH into stETH
        uint256 stETHAmount = IwstETH(asset).unwrap(
            flashLoanWstETHAmount + wstETHBuffer
        );

        // swap stETH for ETH and deposit into WETH - will be pulled by AAVE pool as flash loan repayment
        _swapToWETH(stETHAmount, flashLoanDebt, asset, isFullWithdraw);
    }

    // returns current loan to value, debt and collateral (token) amounts
    function _getCurrentLTV()
        internal
        view
        returns (uint256 loanToValue, uint256 debt, uint256 collateral)
    {
        debt = debtToken.balanceOf(address(this)); // ETH DEBT
        collateral = IwstETH(asset()).getStETHByWstETH(
            interestToken.balanceOf(address(this))
        ); // converted into ETH (stETH) amount;

        (debt == 0 || collateral == 0) ? loanToValue = 0 : loanToValue = debt
            .mulDiv(1e18, collateral, Math.Rounding.Floor);
    }

    // borrow WETH from lending protocol
    // interestRateMode = 2 -> flash loan eth and deposit into cdp, don't repay
    // interestRateMode = 0 -> flash loan eth to repay cdp, have to repay flash loan at the end
    function _flashLoanETH(
        uint256 amount,
        uint256 assetsToWithdraw,
        uint256 interestRateMode,
        bool isFullWithdraw
    ) internal {
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
            abi.encode(isWithdraw, isFullWithdraw, assetsToWithdraw),
            0
        );
    }

    // swaps stETH to WETH
    function _swapToWETH(
        uint256 amount,
        uint256 minAmount,
        address asset,
        bool isFullWithdraw
    ) internal returns (uint256 amountWETHReceived) {
        amountWETHReceived = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            amount,
            minAmount
        );
        weth.deposit{value: minAmount}(); // wrap precise amount of eth for flash loan repayment
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    // amount of WETH to borrow OR amount of WETH to repay (converted into wstETH amount internally)
    function adjustLeverage() public {
        // get vault current leverage : debt/collateral
        (
            uint256 currentLTV,
            uint256 currentDebt,
            uint256 currentCollateral
        ) = _getCurrentLTV();

        // de-leverage if vault LTV is higher than target
        if (currentLTV > targetLTV) {
            uint256 amountETH = (currentDebt -
                (
                    targetLTV.mulDiv(
                        (currentCollateral),
                        1e18,
                        Math.Rounding.Floor
                    )
                )).mulDiv(1e18, (1e18 - targetLTV), Math.Rounding.Floor);

            // flash loan eth to repay part of the debt
            _flashLoanETH(amountETH, 0, 0, false);
        } else {
            uint256 amountETH = (targetLTV.mulDiv(
                currentCollateral,
                1e18,
                Math.Rounding.Floor
            ) - currentDebt).mulDiv(
                    1e18,
                    (1e18 - targetLTV),
                    Math.Rounding.Floor
                );

            // use eventual ETH dust remained in the contract
            amountETH -= address(this).balance;

            // flash loan WETH from lending protocol and add to cdp
            _flashLoanETH(amountETH, 0, 2, false);
        }
    }

    function withdrawDust(address recipient) public onlyOwner {
        // send eth dust to recipient
        (bool sent, ) = address(recipient).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send ETH");
    }

    function setLeverageValues(
        uint256 targetLTV_,
        uint256 maxLTV_,
        uint256 slippage_
    ) external onlyOwner {
        targetLTV = targetLTV_;
        maxLTV = maxLTV_;

        adjustLeverage();

        slippage = slippage_;
    }

    bool internal initCollateral;

    function setUserUseReserveAsCollateral(uint256 amount) external onlyOwner {
        if (initCollateral) revert InvalidInitialization();
        address asset_ = asset();

        IERC20(asset_).safeTransferFrom(msg.sender, address(this), amount);
        lendingPool.supply(asset_, amount, address(this), 0);

        lendingPool.setUserUseReserveAsCollateral(asset_, true);
        
        initCollateral = true;
    }
}
