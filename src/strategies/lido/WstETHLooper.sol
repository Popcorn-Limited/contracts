// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../BaseStrategy.sol";
import {IwstETH} from "./IwstETH.sol";
import {ILido} from "./ILido.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IWETH} from "../../interfaces/external/IWETH.sol";
import {ICurveMetapool} from "../../interfaces/external/curve/ICurveMetapool.sol";
import {
    ILendingPool,
    IAToken,
    IFlashLoanReceiver,
    IProtocolDataProvider,
    IPoolAddressesProvider,
    DataTypes
} from "../../interfaces/external/aave/IAaveV3.sol";

struct LooperInitValues {
    address aaveDataProvider;
    address curvePool;
    uint256 maxLTV;
    address poolAddressesProvider;
    uint256 slippage;
    uint256 targetLTV;
}

/// @title Leveraged wstETH yield adapter
/// @author Andrea Di Nenno
/// @notice ERC4626 wrapper for leveraging stETH yield
/// @dev The strategy takes wstETH and deposits it into a lending protocol (aave).
/// Then it borrows ETH, swap for wstETH and redeposits it
contract WstETHLooper is BaseStrategy, IFlashLoanReceiver {
    // using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // address of the aave/spark router
    ILendingPool public lendingPool;
    IPoolAddressesProvider public poolAddressesProvider;

    IWETH public constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant stETH = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    IERC20 public debtToken; // aave eth debt token
    IERC20 public interestToken; // aave awstETH

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;

    ICurveMetapool public stableSwapStETH;

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

        // retrieve and set wstETH aToken, lending pool
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

        // retrieve and set WETH variable debt token
        (,, address _variableDebtToken) =
            IProtocolDataProvider(initValues.aaveDataProvider).getReserveTokensAddresses(address(weth));

        debtToken = IERC20(_variableDebtToken); // variable debt WETH token

        _name = string.concat("VaultCraft Leveraged ", IERC20Metadata(asset_).name(), " Adapter");
        _symbol = string.concat("vc-", IERC20Metadata(asset_).symbol());

        // approve aave router to pull wstETH
        IERC20(asset_).approve(address(lendingPool), type(uint256).max);

        // approve aave pool to pull WETH as part of a flash loan
        IERC20(address(weth)).approve(address(lendingPool), type(uint256).max);

        // approve curve router to pull stETH for swapping
        stableSwapStETH = ICurveMetapool(initValues.curvePool);
        IERC20(stETH).approve(address(stableSwapStETH), type(uint256).max);

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
        uint256 debt = ILido(stETH).getSharesByPooledEth(debtToken.balanceOf(address(this))); // wstETH DEBT
        uint256 collateral = interestToken.balanceOf(address(this)); // wstETH collateral

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
        (ltv,,) = _getCurrentLTV();
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

        (bool isWithdraw, bool isFullWithdraw, uint256 assetsToWithdraw, uint256 depositAmount) =
            abi.decode(params, (bool, bool, uint256, uint256));

        if (isWithdraw) {
            // flash loan is to repay ETH debt as part of a withdrawal
            uint256 flashLoanDebt = amounts[0] + premiums[0];

            // repay cdp WETH debt
            lendingPool.repay(address(weth), amounts[0], 2, address(this));

            // withdraw collateral, swap, repay flashloan
            _reduceLeverage(isFullWithdraw, assetsToWithdraw, flashLoanDebt);
        } else {
            // flash loan is to leverage UP
            _redepositAsset(amounts[0], depositAmount);
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit wstETH into lending protocol
    function _protocolDeposit(uint256 assets, uint256, bytes memory) internal override {
        // deposit wstETH into aave - receive aToken here
        lendingPool.supply(asset(), assets, address(this), 0);
    }

    /// @notice repay part of the vault debt and withdraw wstETH
    function _protocolWithdraw(uint256 assets, uint256, bytes memory) internal override {
        (, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV();
        uint256 ethAssetsValue = ILido(stETH).getPooledEthByShares(assets);
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
            _flashLoanETH(debtToRepay, 0, assets, 0, isFullWithdraw);
        }

        // reverts if LTV got above max
        _assertHealthyLTV();
    }

    // deposit back into the protocol
    // either from flash loan or simply ETH dust held by the adapter
    function _redepositAsset(uint256 borrowAmount, uint256 depositAmount) internal {
        address wstETH = asset();

        if (borrowAmount > 0) {
            // unwrap into ETH the flash loaned amount
            weth.withdraw(borrowAmount);
        }

        // stake borrowed eth and receive wstETH
        (bool sent,) = wstETH.call{value: depositAmount}("");
        require(sent, "Fail to send eth to wstETH");

        // get wstETH balance after staking
        // may include eventual wstETH dust held by contract somehow
        // in that case it will just add more collateral
        uint256 wstETHAmount = IERC20(wstETH).balanceOf(address(this));

        // deposit wstETH into lending protocol
        _protocolDeposit(wstETHAmount, 0, hex"");
    }

    // reduce leverage by withdrawing wstETH, swapping to ETH repaying ETH debt
    // repayAmount is a ETH (wETH) amount
    function _reduceLeverage(bool isFullWithdraw, uint256 toWithdraw, uint256 flashLoanDebt) internal {
        address asset = asset();

        // get flash loan amount converted in wstETH
        uint256 flashLoanWstETHAmount = ILido(stETH).getSharesByPooledEth(flashLoanDebt);

        // get slippage buffer for swapping with flashLoanDebt as minAmountOut
        uint256 wstETHBuffer = flashLoanWstETHAmount.mulDiv(slippage, 1e18, Math.Rounding.Floor);

        // withdraw wstETH from aave
        if (isFullWithdraw) {
            // withdraw all
            lendingPool.withdraw(asset, type(uint256).max, address(this));
        } else {
            lendingPool.withdraw(asset, flashLoanWstETHAmount + wstETHBuffer + toWithdraw, address(this));
        }

        // unwrap wstETH into stETH
        uint256 stETHAmount = IwstETH(asset).unwrap(flashLoanWstETHAmount + wstETHBuffer);

        // swap stETH for ETH and deposit into WETH - will be pulled by AAVE pool as flash loan repayment
        _swapToWETH(stETHAmount, flashLoanDebt, asset, toWithdraw);
    }

    // returns current loan to value, debt and collateral (token) amounts
    function _getCurrentLTV() internal view returns (uint256 loanToValue, uint256 debt, uint256 collateral) {
        debt = debtToken.balanceOf(address(this)); // ETH DEBT
        collateral = ILido(stETH).getPooledEthByShares(interestToken.balanceOf(address(this))); // converted into ETH amount;

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
    function _assertHealthyLTV() internal view {
        (uint256 currentLTV, ,) = _getCurrentLTV();

        if (currentLTV > maxLTV)
            revert BadLTV(currentLTV, maxLTV);
    }

    // borrow WETH from lending protocol
    // interestRateMode = 2 -> flash loan eth and deposit into cdp, don't repay
    // interestRateMode = 0 -> flash loan eth to repay cdp, have to repay flash loan at the end
    function _flashLoanETH(
        uint256 borrowAmount,
        uint256 depositAmount,
        uint256 assetsToWithdraw,
        uint256 interestRateMode,
        bool isFullWithdraw
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
            abi.encode(interestRateMode == 0 ? true : false, isFullWithdraw, assetsToWithdraw, depositAmount_),
            0
        );
    }

    // swaps stETH to WETH
    function _swapToWETH(uint256 amount, uint256 minAmount, address asset, uint256 wstETHToWithdraw)
        internal
        returns (uint256 amountETHReceived)
    {
        // swap to ETH
        amountETHReceived = stableSwapStETH.exchange(STETHID, WETHID, amount, minAmount);

        // wrap precise amount of eth for flash loan repayment
        weth.deposit{value: minAmount}();

        // restake the eth needed to reach the wstETH amount the user is withdrawing
        uint256 missingWstETH = wstETHToWithdraw - IERC20(asset).balanceOf(address(this)) + 1;
        if (missingWstETH > 0) {
            uint256 ethAmount = ILido(stETH).getPooledEthByShares(missingWstETH);

            // stake eth to receive wstETH
            (bool sent,) = asset.call{value: ethAmount}("");
            require(sent, "Fail to send eth to wstETH");
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setHarvestValues(address curveSwapPool) external onlyOwner {
        // reset old pool
        IERC20(stETH).approve(address(stableSwapStETH), 0);

        // set and approve new one
        stableSwapStETH = ICurveMetapool(curveSwapPool);
        IERC20(stETH).approve(address(stableSwapStETH), type(uint256).max);
    }

    function harvest(bytes memory) external override onlyKeeperOrOwner {
        adjustLeverage();

        emit Harvested();
    }

    // amount of WETH to borrow OR amount of WETH to repay (converted into wstETH amount internally)
    function adjustLeverage() public {
        // get vault current leverage : debt/collateral
        (uint256 currentLTV, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV();

        // de-leverage if vault LTV is higher than target
        if (currentLTV > targetLTV) {
            uint256 amountETH = (currentDebt - (targetLTV.mulDiv((currentCollateral), 1e18, Math.Rounding.Floor)))
                .mulDiv(1e18, (1e18 - targetLTV), Math.Rounding.Ceil);

            // flash loan eth to repay part of the debt
            _flashLoanETH(amountETH, 0, 0, 0, false);
        } else {
            uint256 amountETH = (targetLTV.mulDiv(currentCollateral, 1e18, Math.Rounding.Ceil) - currentDebt).mulDiv(
                1e18, (1e18 - targetLTV), Math.Rounding.Ceil
            );

            uint256 dustBalance = address(this).balance;
            if (dustBalance < amountETH) {
                // flashloan but use eventual ETH dust remained in the contract as well
                uint256 borrowAmount = amountETH - dustBalance;

                // flash loan WETH from lending protocol and add to cdp
                _flashLoanETH(borrowAmount, amountETH, 0, 2, false);
            } else {
                // deposit the dust as collateral- borrow amount is zero
                // leverage naturally decreases
                _redepositAsset(0, dustBalance);
            }
        }

        // reverts if LTV got above max
        _assertHealthyLTV();
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
