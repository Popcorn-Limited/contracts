// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ICToken, IComptroller} from "src/interfaces/external/compound/v2/ICompoundV2.sol";
import {LibCompound} from "src/interfaces/external/compound/v2/LibCompound.sol";
import {ILendingPool, IFlashLoanReceiver, IPoolAddressesProvider} from "src/interfaces/external/aave/IAaveV3.sol";

struct LooperBaseValues {
    address aaveLendingPool;
    address borrowAssetCToken; // asset to borrow (ie WETH - wMATIC)
    address cToken;
    uint256 maxLTV;
    uint256 maxSlippage;
    address poolAddressesProvider;
    uint256 targetLTV;
}

struct FlashLoanCache {
    bool toIncreaseLeverage;
    bool isFullWithdraw;
    uint256 assetsToWithdraw;
    uint256 depositAmount;
    uint256 slippage;
}

abstract contract BaseCompoundV2LeverageStrategy is BaseStrategy, IFlashLoanReceiver {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    address constant COMP = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);

    IComptroller public comptroller; // Comp router

    IERC20 public borrowAsset; // asset to borrow
    ICToken public borrowCToken; // borrow cToken
    ICToken public collateralToken; // Comp cToken
    ILendingPool public aaveLendingPool; // aave pool for flash loan
    IPoolAddressesProvider public poolAddressesProvider; // aave pool provider

    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage
    uint256 public targetLTV; // in 18 decimals - 1e17 being 0.1%
    uint256 public maxLTV; // max ltv the vault can reach
    uint256 public protocolMaxLTV; // underlying money market max LTV

    error InvalidComptroller(address cToken, address borrowCToken);
    error InvalidCToken(address cToken, address asset);
    error InvalidLTV(uint256 targetLTV, uint256 maxLTV, uint256 protocolLTV);
    error InvalidSlippage(uint256 slippage, uint256 slippageCap);
    error BadLTV(uint256 currentLTV, uint256 maxLTV);

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoDeposit_ Controls if `protocolDeposit` gets called on deposit
     * @param initValues Encoded data for this specific strategy
     */
    function __BaseLeverageStrategy_init(
        address asset_,
        address owner_,
        bool autoDeposit_,
        LooperBaseValues memory initValues
    ) internal onlyInitializing {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        // init cTokens, comptroller
        collateralToken = ICToken(initValues.cToken);
        if(collateralToken.underlying() != asset_)
            revert InvalidCToken(initValues.cToken, asset_);

        borrowCToken = ICToken(initValues.borrowAssetCToken);
        borrowAsset = IERC20(borrowCToken.underlying());

        comptroller = IComptroller(collateralToken.comptroller());
        if(borrowCToken.comptroller() != address(comptroller))
            revert InvalidComptroller(address(collateralToken), address(borrowCToken));

        // init aave addresses
        aaveLendingPool = ILendingPool(initValues.aaveLendingPool);
        poolAddressesProvider = IPoolAddressesProvider(
            initValues.poolAddressesProvider
        );

        // verify LTV values
        protocolMaxLTV = _getMaxLTV();

        _verifyLTV(initValues.targetLTV, initValues.maxLTV, protocolMaxLTV);

        targetLTV = initValues.targetLTV;
        maxLTV = initValues.maxLTV;

        _name = string.concat(
            "VaultCraft Compound Leveraged ",
            IERC20Metadata(asset_).name(),
            " Strategy"
        );
        _symbol = string.concat("vc-", IERC20Metadata(asset_).symbol());

        // approve Comp router to pull asset
        IERC20(asset_).approve(address(comptroller), type(uint256).max);

        // approve aave pool to pull borrow asset as part of a flash loan
        IERC20(address(borrowAsset)).approve(
            address(aaveLendingPool),
            type(uint256).max
        );

        // set slippage
        if (initValues.maxSlippage > 2e17) {
            revert InvalidSlippage(initValues.maxSlippage, 2e17);
        }

        slippage = initValues.maxSlippage;
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
        // get value of debt in collateral tokens
        uint256 debtValue = _toCollateralValue(
            LibCompound.viewBorrowBalance(borrowCToken, address(this))
        );

        // get collateral amount
        uint256 collateral = LibCompound.viewUnderlyingBalanceOf(collateralToken, address(this));

        if (debtValue >= collateral) return 0;

        uint256 total = collateral;
        if (debtValue > 0) {
            total -= debtValue;

            // if there's debt, apply slippage to repay it
            uint256 slippageDebt = debtValue.mulDiv(
                slippage,
                1e18,
                Math.Rounding.Ceil
            );

            if (slippageDebt >= total) return 0;

            total -= slippageDebt;
        }
        if (total > 0) return total - 1;
        else return 0;
    }

    function getLTV() public view returns (uint256 ltv) {
        (ltv, , ) = _getCurrentLTV();
    }

    // must provide logic to retrieve the money market max ltv
    function _getMaxLTV() internal view returns (uint256 protocolLTV) {
        (, protocolLTV, ) = comptroller.markets(address(collateralToken));
    }

    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        revert();
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    function adjustLeverage() public {
        // get vault current leverage : debt/collateral
        (
            uint256 currentLTV,
            uint256 currentDebt,
            uint256 currentCollateral
        ) = _getCurrentLTV();

        if (currentLTV > targetLTV) {
            // de-leverage if vault LTV is higher than target
            uint256 borrowAmount = (currentDebt -
                (
                    targetLTV.mulDiv(
                        (currentCollateral),
                        1e18,
                        Math.Rounding.Floor
                    )
                )).mulDiv(1e18, (1e18 - targetLTV), Math.Rounding.Ceil);

            // flash loan debt asset to repay part of the debt
            _flashLoan(borrowAmount, 0, 0, false, false, slippage);
        } else {
            uint256 depositAmount = (targetLTV.mulDiv(
                currentCollateral,
                1e18,
                Math.Rounding.Ceil
            ) - currentDebt).mulDiv(
                    1e18,
                    (1e18 - targetLTV),
                    Math.Rounding.Ceil
                );

            uint256 dustBalance = address(this).balance;

            if (dustBalance < depositAmount) {
                // flashloan but use eventual collateral dust remained in the contract as well
                uint256 borrowAmount = depositAmount - dustBalance;

                // flash loan debt asset from aave, swap for collateral, 
                // deposit into compound, borrow debt to repay aave flash loan
                _flashLoan(borrowAmount, depositAmount, 0, true, false, 0);
            } else {
                // deposit the dust as collateral- borrow amount is zero
                // leverage naturally decreases
                _redepositAsset(0, dustBalance, asset());
            }
        }

        // reverts if LTV got above max
        _assertHealthyLTV();
    }

    /// @notice The token rewarded if the Comp liquidity mining is active
    function rewardTokens() external view override returns (address[] memory rewAddr) {
        rewAddr = new address[](1);
        rewAddr[0] = COMP;
    }

    /// @notice Claim additional rewards given that it's active.
    function claim() internal override returns (bool success) {
        comptroller.claimComp(address(this));
        return true;
    }

    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        uint256 balance = IERC20(COMP).balanceOf(address(this));
        if (balance > 0)
            IERC20(COMP).transfer(msg.sender, balance);

        uint256 assetAmount = abi.decode(data, (uint256));

        if (assetAmount == 0) revert ZeroAmount();

        IERC20(asset()).transferFrom(msg.sender, address(this), assetAmount);

        _protocolDeposit(assetAmount, 0, bytes(""));

        emit Harvested();
    }

    function setHarvestValues(bytes memory harvestValues) external onlyOwner {
        _setHarvestValues(harvestValues);
    }

    function setLeverageValues(
        uint256 targetLTV_,
        uint256 maxLTV_
    ) external onlyOwner {
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

    function withdrawDust(address recipient) public onlyOwner {
        _withdrawDust(recipient);
    }

    /*//////////////////////////////////////////////////////////////
                          FLASH LOAN LOGIC
    //////////////////////////////////////////////////////////////*/

    error NotFlashLoan();

    function ADDRESSES_PROVIDER()
        external
        view
        returns (IPoolAddressesProvider)
    {
        return poolAddressesProvider;
    }

    function POOL() external view returns (ILendingPool) {
        return aaveLendingPool;
    }

    // this is triggered after the flash loan is given, ie contract has loaned assets at this point
    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (initiator != address(this) || msg.sender != address(aaveLendingPool)) {
            revert NotFlashLoan();
        }

        FlashLoanCache memory cache = abi.decode(params, (FlashLoanCache));

        uint256 flashLoanDebt = amounts[0] + premiums[0];
        
        if (!cache.toIncreaseLeverage) {
            // repay cdp debt on compound
            borrowCToken.repayBorrow(amounts[0]);

            // withdraw collateral, swap, repay flashloan
            _reduceLeverage(
                cache.isFullWithdraw,
                asset(),
                cache.assetsToWithdraw,
                flashLoanDebt,
                cache.slippage
            );
        } else {
            // flash loan is to leverage UP
            // deposit assets
            _redepositAsset(amounts[0], cache.depositAmount, asset());

            // borrow from compound in order to repay aave flash loan
            borrowCToken.borrow(flashLoanDebt);
        }

        return true;
    }

    // borrow asset from aave
    // toIncreaseLeverage = true -> flash loan asset token, deposit into compound, borrow assets to repay the flash loan
    // toIncreaseLeverage = false -> flash loan debt token, repay compound cdp, withdraw collateral to repay flash loan
    function _flashLoan(
        uint256 borrowAmount,
        uint256 depositAmount,
        uint256 assetsToWithdraw,
        bool toIncreaseLeverage,
        bool isFullWithdraw,
        uint256 slippage
    ) internal {
        // uint256 depositAmount_ = depositAmount; // avoids stack too deep
        FlashLoanCache memory cache = FlashLoanCache(
            toIncreaseLeverage,
            isFullWithdraw,
            assetsToWithdraw,
            depositAmount,
            slippage
        );

        address[] memory assets = new address[](1);
        assets[0] = toIncreaseLeverage ? asset() : address(borrowAsset);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = borrowAmount;

        // always a flash loan to be repaid
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0; 

        aaveLendingPool.flashLoan(
            address(this),
            assets,
            amounts,
            interestRateModes,
            address(this),
            abi.encode(cache),
            0
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    error DepositFailed(uint256 assets, uint256 res);

    /// @notice Deposit asset into compound
    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        uint256 res = collateralToken.mint(assets);
        if(res != 0)
            revert DepositFailed(assets,res);
    }

    /// @notice repay part of the vault debt if necessary and withdraw asset
    function _protocolWithdraw(
        uint256 assets,
        uint256,
        bytes memory extraData
    ) internal override {
        (
            ,
            uint256 totalDebt,
            uint256 totalCollateralDebtValue
        ) = _getCurrentLTV();

        uint256 assetsDebtValue = _toDebtValue(assets);

        bool isFullWithdraw;
        uint256 ratioDebtToRepay;

        {
            uint256 debtSlippage = totalDebt.mulDiv(
                slippage,
                1e18,
                Math.Rounding.Ceil
            );

            // find the % of debt to repay as the % of collateral being withdrawn
            ratioDebtToRepay = assetsDebtValue.mulDiv(
                1e18,
                (totalCollateralDebtValue - totalDebt - debtSlippage),
                Math.Rounding.Floor
            );

            isFullWithdraw =
                assets == _totalAssets() ||
                ratioDebtToRepay >= 1e18;
        }

        // get the LTV we would have without repaying debt
        uint256 futureLTV = isFullWithdraw
            ? type(uint256).max
            : totalDebt.mulDiv(
                1e18,
                (totalCollateralDebtValue - assetsDebtValue),
                Math.Rounding.Floor
            );

        if (futureLTV <= maxLTV || totalDebt == 0) {
            // 1 - withdraw any asset amount with no debt
            // 2 - withdraw assets with debt but the change doesn't take LTV above max
            collateralToken.redeemUnderlying(assets);
        } else {
            // 1 - withdraw assets but repay debt
            uint256 debtToRepay = isFullWithdraw
                ? totalDebt
                : totalDebt.mulDiv(ratioDebtToRepay, 1e18, Math.Rounding.Floor);

            // flash loan debtToRepay - flash loan is repaid at the end
            _flashLoan(debtToRepay, 0, assets, false, isFullWithdraw, slippage);
        }

        // reverts if LTV got above max
        _assertHealthyLTV();
    }

    ///@notice called after a flash loan to repay cdp
    function _reduceLeverage(
        bool isFullWithdraw,
        address asset,
        uint256 toWithdraw,
        uint256 flashLoanDebt,
        uint256 slippage
    ) internal {
        // get flash loan amount converted in collateral value
        uint256 flashLoanCollateralValue = _toCollateralValue(flashLoanDebt);

        // get slippage buffer for swapping and repaying flashLoanDebt
        uint256 swapBuffer = flashLoanCollateralValue.mulDiv(
            slippage,
            1e18,
            Math.Rounding.Floor
        );

        // if the withdraw amount with buffer is greater than total assets withdraw all
        if (
            flashLoanCollateralValue + swapBuffer + toWithdraw >= _totalAssets()
        ) isFullWithdraw = true;

        if (isFullWithdraw) {
            // withdraw all
            collateralToken.redeem(collateralToken.balanceOf(address(this)));
        } else {
            collateralToken.redeemUnderlying(
                flashLoanCollateralValue + swapBuffer + toWithdraw
            );
        }

        // swap collateral to exact debt asset - will be pulled by aave pool as flash loan repayment
        _convertCollateralToDebt(
            flashLoanCollateralValue + swapBuffer,
            flashLoanDebt,
            asset,
            toWithdraw
        );
    }

    // deposit back into the protocol 
    // either from flash loan or simply collateral dust held by the strategy
    function _redepositAsset(
        uint256 borrowAmount,
        uint256 totCollateralAmount,
        address asset
    ) internal {
        // use borrow asset to get more collateral
        _convertDebtToCollateral(borrowAmount, totCollateralAmount);

        // deposit collateral balance into lending protocol
        // may include eventual dust held by contract somehow
        // in that case it will just add more collateral
        _protocolDeposit(IERC20(asset).balanceOf(address(this)), 0, hex"");
    }

    // returns current loan to value
    // debt and collateral amounts in debt value
    function _getCurrentLTV()
        internal
        view
        returns (uint256 loanToValue, uint256 debt, uint256 collateral)
    {
        debt = LibCompound.viewBorrowBalance(borrowCToken, address(this)); // debt
        collateral = _toDebtValue(
            LibCompound.viewUnderlyingBalanceOf(collateralToken, address(this))
        ); // collateral converted into debt amount;

        // LTV = borrowedValue / collateralValue
        if(collateral != 0)
            loanToValue = debt.mulDiv(1e18, collateral, Math.Rounding.Ceil);
    }

    // reverts if targetLTV < maxLTV < protocolLTV is not satisfied
    function _verifyLTV(
        uint256 _targetLTV,
        uint256 _maxLTV,
        uint256 _protocolLTV
    ) internal pure {
        if (_targetLTV >= _maxLTV || _maxLTV >= _protocolLTV) {
            revert InvalidLTV(_targetLTV, _maxLTV, _protocolLTV);
        }
    }

    // verify that currentLTV is not above maxLTV
    function _assertHealthyLTV() internal view {
        (uint256 currentLTV, , ) = _getCurrentLTV();

        if (currentLTV > maxLTV) {
            revert BadLTV(currentLTV, maxLTV);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          TO OVERRIDE IN IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    // must provide conversion from debt asset to vault (collateral) asset
    function _toCollateralValue(
        uint256 debtAmount
    ) internal view virtual returns (uint256 collateralAmount);

    // must provide conversion from vault (collateral) asset to debt asset
    function _toDebtValue(
        uint256 collateralAmount
    ) internal view virtual returns (uint256 debtAmount);

    // must provide logic to go from collateral to debt assets
    function _convertCollateralToDebt(
        uint256 maxCollateralIn,
        uint256 exactDebtAmont,
        address asset,
        uint256 toWithdraw
    ) internal virtual;

    // must provide logic to use borrowed debt assets to get collateral
    function _convertDebtToCollateral(
        uint256 debtAmount,
        uint256 totCollateralAmount
    ) internal virtual;

    // must provide logic to decode and assign harvest values
    function _setHarvestValues(bytes memory harvestValues) internal virtual;

    // must provide logic to withdraw dust assets
    function _withdrawDust(address recipient) internal virtual;
}
