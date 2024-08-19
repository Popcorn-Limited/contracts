// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {ICurveMetapool} from "src/interfaces/external/curve/ICurveMetapool.sol";
import {IETHxStaking} from "./IETHxStaking.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IWETH} from "src/interfaces/external/IWETH.sol";
import {
    ILendingPool,
    IAToken,
    IFlashLoanReceiver,
    IProtocolDataProvider,
    IPoolAddressesProvider,
    DataTypes
} from "src/interfaces/external/aave/IAaveV3.sol";

struct LooperInitValues {
    address aaveDataProvider;
    address curvePool;
    address ethXPool;
    uint256 maxLTV;
    address poolAddressesProvider;
    uint256 slippage;
    uint256 targetLTV;
}

struct FlashLoanCache {
    bool isWithdraw; 
    bool isFullWithdraw;
    uint256 assetsToWithdraw;
    uint256 depositAmount; 
    uint256 exchangeRate;
}

/// @title Leveraged ETHx yield adapter
/// @author Andrea Di Nenno
/// @notice ERC4626 wrapper for leveraging ETHx yield
/// @dev The strategy takes ETHx and deposits it into a lending protocol (aave).
/// Then it borrows WETH, swap for ETHx and redeposits it
contract ETHXLooper is BaseStrategy, IFlashLoanReceiver {
    // using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // address of the aave/spark router
    ILendingPool public lendingPool;
    IPoolAddressesProvider public poolAddressesProvider;

    IWETH public constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IETHxStaking public stakingPool; // stader pool for wrapping - converting
    
    IERC20 public debtToken; // aave eht debt token
    IERC20 public interestToken; // aave aETHx

    int128 private constant WETHID = 0;
    int128 private constant ETHxID = 1;

    ICurveMetapool public stableSwapPool;

    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage

    uint256 public targetLTV; // in 18 decimals - 1e17 being 0.1%
    uint256 public maxLTV; // max ltv the vault can reach
    uint256 public protocolMaxLTV; // underlying money market max LTV

    error InvalidLTV(uint256 targetLTV, uint256 maxLTV, uint256 protocolLTV);
    error InvalidSlippage(uint256 slippage, uint256 slippageCap);
    error BadLTV(uint256 currentLTV, uint256 maxLTV);
    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(address asset_, address owner_, bool autoDeposit_, bytes memory strategyInitData_)
        public
        initializer
    {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        LooperInitValues memory initValues = abi.decode(strategyInitData_, (LooperInitValues));

        stakingPool = IETHxStaking(initValues.ethXPool);

        // retrieve and set ethX aToken, lending pool
        (address _aToken,,) = IProtocolDataProvider(initValues.aaveDataProvider).getReserveTokensAddresses(asset_);
        interestToken = IERC20(_aToken);
        lendingPool = ILendingPool(IAToken(_aToken).POOL());

        // set efficiency mode - ETH correlated
        lendingPool.setUserEMode(uint8(1));

        // get protocol LTV
        DataTypes.EModeData memory emodeData = lendingPool.getEModeCategoryData(uint8(1));
        protocolMaxLTV = uint256(emodeData.maxLTV) * 1e14; // make it 18 decimals to compare;

        // check ltv init values are correct
        _verifyLTV(initValues.targetLTV, initValues.maxLTV, protocolMaxLTV);

        targetLTV = initValues.targetLTV;
        maxLTV = initValues.maxLTV;

        poolAddressesProvider = IPoolAddressesProvider(initValues.poolAddressesProvider);

        // retrieve and set weth variable debt token
        (,, address _variableDebtToken) =
            IProtocolDataProvider(initValues.aaveDataProvider).getReserveTokensAddresses(address(weth));

        debtToken = IERC20(_variableDebtToken); // variable debt weth token

        _name = string.concat("VaultCraft Leveraged ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vc-", IERC20Metadata(asset_).symbol());

        // approve aave router to pull EThx
        IERC20(asset_).approve(address(lendingPool), type(uint256).max);

        // approve aave pool to pull WETH as part of a flash loan
        IERC20(address(weth)).approve(address(lendingPool), type(uint256).max);

        // approve curve to pull ETHx for swapping
        stableSwapPool = ICurveMetapool(initValues.curvePool);
        IERC20(asset_).approve(address(stableSwapPool), type(uint256).max);

        // set slippage
        if (initValues.slippage > 2e17) {
            revert InvalidSlippage(initValues.slippage, 2e17);
        }

        slippage = initValues.slippage;
    }

    receive() external payable {}

    function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/
    function _totalAssets() internal view override returns (uint256) {
        uint256 ethToEthXRate = stakingPool.getExchangeRate();
        uint256 debt = debtToken.balanceOf(address(this)).mulDiv(1e18, ethToEthXRate, Math.Rounding.Ceil); // weth debt converted in ethX amount
        
        uint256 collateral = interestToken.balanceOf(address(this)); // ethX collateral

        if (debt >= collateral) return 0;

        uint256 total = collateral;
        if (debt > 0) {
            total -= debt;

            // if there's debt, apply slippage to repay it
            uint256 slippageDebt = debt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

            if (slippageDebt >= total) return 0;

            total -= slippageDebt;
        }
        if (total > 0) return total - 1;
        else return 0;
    }

    function getLTV() public view returns (uint256 ltv) {
        (ltv,,) = _getCurrentLTV(stakingPool.getExchangeRate());
    }

    /*//////////////////////////////////////////////////////////////
                          FLASH LOAN LOGIC
    //////////////////////////////////////////////////////////////*/

    error NotFlashLoan();

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return poolAddressesProvider;
    }

    function POOL() external view returns (ILendingPool) {
        return lendingPool;
    }

    // this is triggered after the flash loan is given, ie contract has loaned assets at this point
    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (initiator != address(this) || msg.sender != address(lendingPool)) {
            revert NotFlashLoan();
        }

        FlashLoanCache memory cache = abi.decode(params, (FlashLoanCache));

        if (cache.isWithdraw) {
            // flash loan is to repay weth debt as part of a withdrawal
            uint256 flashLoanDebt = amounts[0] + premiums[0];

            // repay cdp weth debt
            lendingPool.repay(address(weth), amounts[0], 2, address(this));

            // withdraw collateral, swap, repay flashloan
            _reduceLeverage(cache.isFullWithdraw, cache.assetsToWithdraw, flashLoanDebt, cache.exchangeRate);
        } else {
            // flash loan is to leverage UP
            _redepositAsset(amounts[0], cache.depositAmount);
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit ethX into lending protocol
    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal override {
        // deposit ethX into aave - receive aToken here
        lendingPool.supply(asset(), assets, address(this), 0);
    }

    /// @notice repay part of the vault debt and withdraw ethX
    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal override {
        uint256 ethToEthXRate = stakingPool.getExchangeRate();

        (, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV(ethToEthXRate);
        uint256 ethAssetsValue = assets.mulDiv(1e18, ethToEthXRate, Math.Rounding.Ceil);
        
        bool isFullWithdraw;
        uint256 ratioDebtToRepay;

        {
            uint256 debtSlippage = currentDebt.mulDiv(slippage, 1e18, Math.Rounding.Ceil);

            // find the % of debt to repay as the % of collateral being withdrawn
            ratioDebtToRepay =
                ethAssetsValue.mulDiv(1e18, (currentCollateral - currentDebt - debtSlippage), Math.Rounding.Floor);

            isFullWithdraw = assets == _totalAssets() || ratioDebtToRepay >= 1e18;
        }

        // get the LTV we would have without repaying debt
        uint256 futureLTV = isFullWithdraw
            ? type(uint256).max
            : currentDebt.mulDiv(1e18, (currentCollateral - ethAssetsValue), Math.Rounding.Floor);

        if (futureLTV <= maxLTV || currentDebt == 0) {
            // 1 - withdraw any asset amount with no debt
            // 2 - withdraw assets with debt but the change doesn't take LTV above max
            lendingPool.withdraw(asset(), assets, address(this));
        } else {
            // 1 - withdraw assets but repay debt
            uint256 debtToRepay =
                isFullWithdraw ? currentDebt : currentDebt.mulDiv(ratioDebtToRepay, 1e18, Math.Rounding.Floor);

            // flash loan debtToRepay - mode 0 - flash loan is repaid at the end
            _flashLoanETH(debtToRepay, 0, assets, 0, isFullWithdraw, ethToEthXRate);
        }

        // reverts if LTV got above max
        _assertHealthyLTV(ethToEthXRate);
    }

    // deposit back into the protocol
    // either from flash loan or simply ETH dust held by the adapter
    function _redepositAsset(uint256 borrowAmount, uint256 depositAmount) internal {
        address ethX = asset();

        if (borrowAmount > 0) {
            // unwrap into ETH the flash loaned amount
            weth.withdraw(borrowAmount);
        }

        // stake borrowed eth and receive ethX
        stakingPool.deposit{value: depositAmount}(address(this));

        // get ethX balance after staking
        // may include eventual ethX dust held by contract somehow
        // in that case it will just add more collateral
        uint256 ethXAmount = IERC20(ethX).balanceOf(address(this));

        // deposit ethX into lending protocol
        _protocolDeposit(ethXAmount, 0, hex"");
    }

    // reduce leverage by withdrawing ethX, swapping to ETH repaying weth debt
    function _reduceLeverage(bool isFullWithdraw, uint256 toWithdraw, uint256 flashLoanDebt, uint256 exchangeRate) internal {
        address asset = asset();

        // get flash loan amount converted in ethX
       uint256 flashLoanEthXAmount = flashLoanDebt.mulDiv(1e18, exchangeRate, Math.Rounding.Ceil);

        // get slippage buffer for swapping with flashLoanDebt as minAmountOut
        uint256 ethXBuffer = flashLoanEthXAmount.mulDiv(slippage, 1e18, Math.Rounding.Floor);

        // if the withdraw amount with buffers  to total assets withdraw all
        if (flashLoanEthXAmount + ethXBuffer + toWithdraw >= _totalAssets())
            isFullWithdraw = true;

        // withdraw ethX from aave
        if (isFullWithdraw) {
            // withdraw all
            lendingPool.withdraw(asset, type(uint256).max, address(this));
        } else {
            lendingPool.withdraw(asset, flashLoanEthXAmount + ethXBuffer + toWithdraw, address(this));
        }

        // swap ethX to weth on Curve- will be pulled by AAVE pool as flash loan repayment
        _swapToWETH(flashLoanEthXAmount + ethXBuffer, flashLoanDebt, asset, toWithdraw, exchangeRate);
    }

    // returns current loan to value, debt and collateral (token) amounts
    function _getCurrentLTV(uint256 exchangeRate) internal view returns (uint256 loanToValue, uint256 debt, uint256 collateral) {
        debt = debtToken.balanceOf(address(this)); // WETH DEBT
        collateral = interestToken.balanceOf(address(this)).mulDiv(exchangeRate, 1e18, Math.Rounding.Floor); // converted into ETH amount;

        (debt == 0 || collateral == 0)
            ? loanToValue = 0
            : loanToValue = debt.mulDiv(1e18, collateral, Math.Rounding.Ceil);
    }

    // reverts if targetLTV < maxLTV < protocolLTV is not satisfied
    function _verifyLTV(uint256 _targetLTV, uint256 _maxLTV, uint256 _protocolLTV) internal pure {
        if (_targetLTV >= _maxLTV) {
            revert InvalidLTV(_targetLTV, _maxLTV, _protocolLTV);
        }
        if (_maxLTV >= _protocolLTV) {
            revert InvalidLTV(_targetLTV, _maxLTV, _protocolLTV);
        }
    }

    // verify that currentLTV is not above maxLTV
    function _assertHealthyLTV(uint256 exchangeRate) internal view {
        (uint256 currentLTV,,) = _getCurrentLTV(exchangeRate);

        if (currentLTV > maxLTV) {
            revert BadLTV(currentLTV, maxLTV);
        }
    }

    // borrow weth from lending protocol
    // interestRateMode = 2 -> flash loan eth and deposit into cdp, don't repay
    // interestRateMode = 0 -> flash loan eth to repay cdp, have to repay flash loan at the end
    function _flashLoanETH(
        uint256 borrowAmount,
        uint256 depositAmount,
        uint256 assetsToWithdraw,
        uint256 interestRateMode,
        bool isFullWithdraw,
        uint256 exchangeRate
    ) internal {
        uint256 depositAmount_ = depositAmount; // avoids stack too deep

        address[] memory assets = new address[](1);
        assets[0] = address(weth);


        uint256[] memory amounts = new uint256[](1);
        amounts[0] = borrowAmount;

        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = interestRateMode;

        lendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            interestRateModes,
            address(this),
            abi.encode(interestRateMode == 0 ? true : false, isFullWithdraw, assetsToWithdraw, depositAmount_, exchangeRate),
            0
        );
    }

    // swaps ETHx to exact WETH  
    function _swapToWETH(uint256 amount, uint256 minAmount, address asset, uint256 toWithdraw, uint256 exchangeRate)
        internal
    {
        // swap to ETH
        stableSwapPool.exchange(ETHxID, WETHID, amount, minAmount);

        // wrap precise amount of eth for flash loan repayment
        weth.deposit{value: minAmount}();

        // restake the eth needed to reach the ETHx amount the user is withdrawing
        uint256 missingETHx = toWithdraw - IERC20(asset).balanceOf(address(this)) + 1;
        if (missingETHx > 0) {
            uint256 missingETHAmount = missingETHx.mulDiv(exchangeRate, 1e18, Math.Rounding.Floor);

            // stake eth to receive ETHx
            stakingPool.deposit{value:missingETHAmount}(address(this));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setHarvestValues(address curveSwapPool) external onlyOwner {
        if(curveSwapPool != address(stableSwapPool)) {
            address asset_ = asset();

            // reset old pool
            IERC20(asset_).approve(address(stableSwapPool), 0);

            // set and approve new one
            stableSwapPool = ICurveMetapool(curveSwapPool);
            IERC20(asset_).approve(curveSwapPool, type(uint256).max);
        }
    }

    function harvest(bytes memory) external override onlyKeeperOrOwner {
        adjustLeverage();

        emit Harvested();
    }

    // amount of weth to borrow OR amount of weth to repay (converted into ethX amount internally)
    function adjustLeverage() public {
        uint256 ethToEthXRate = stakingPool.getExchangeRate();

        // get vault current leverage : debt/collateral
        (uint256 currentLTV, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV(ethToEthXRate);

        // de-leverage if vault LTV is higher than target
        if (currentLTV > targetLTV) {
            uint256 amountETH = (currentDebt - (targetLTV.mulDiv((currentCollateral), 1e18, Math.Rounding.Floor)))
                .mulDiv(1e18, (1e18 - targetLTV), Math.Rounding.Ceil);

            // flash loan eth to repay part of the debt
            _flashLoanETH(amountETH, 0, 0, 0, false, ethToEthXRate);
        } else {
            uint256 amountETH = (targetLTV.mulDiv(currentCollateral, 1e18, Math.Rounding.Ceil) - currentDebt).mulDiv(
                1e18, (1e18 - targetLTV), Math.Rounding.Ceil
            );

            uint256 dustBalance = address(this).balance;
            if (dustBalance < amountETH) {
                // flashloan but use eventual ETH dust remained in the contract as well
                uint256 borrowAmount = amountETH - dustBalance;

                // flash loan weth from lending protocol and add to cdp
                _flashLoanETH(borrowAmount, amountETH, 0, 2, false, ethToEthXRate);
            } else {
                // deposit the dust as collateral- borrow amount is zero
                // leverage naturally decreases
                _redepositAsset(0, dustBalance);
            }
        }

        // reverts if LTV got above max
        _assertHealthyLTV(ethToEthXRate);
    }

    function withdrawDust(address recipient) public onlyOwner {
        // send eth dust to recipient
        (bool sent,) = address(recipient).call{value: address(this).balance}("");
        require(sent, "Failed to send ETH");
    }

    function setLeverageValues(uint256 targetLTV_, uint256 maxLTV_) external onlyOwner {
        // reverts if targetLTV < maxLTV < protocolLTV is not satisfied
        _verifyLTV(targetLTV_, maxLTV_, protocolMaxLTV);

        targetLTV = targetLTV_;
        maxLTV = maxLTV_;

        adjustLeverage();
    }

    function setSlippage(uint256 slippage_) external onlyOwner {
        if (slippage_ > 2e17) revert InvalidSlippage(slippage_, 2e17);

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
