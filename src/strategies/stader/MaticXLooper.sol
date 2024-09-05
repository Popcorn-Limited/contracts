// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "src/strategies/BaseStrategy.sol";
import {IMaticXPool} from "./IMaticX.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {IWETH as IWMatic} from "src/interfaces/external/IWETH.sol";
import {ILendingPool, IAToken, IFlashLoanReceiver, IProtocolDataProvider, IAaveIncentives, IPoolAddressesProvider, DataTypes} from "src/interfaces/external/aave/IAaveV3.sol";
import {IBalancerVault, SwapKind, SingleSwap, FundManagement} from "src/interfaces/external/balancer/IBalancer.sol";

struct LooperInitValues {
    address aaveDataProvider;
    address balancerVault;
    address maticXPool;
    uint256 maxLTV;
    address poolAddressesProvider;
    bytes32 poolId;
    uint256 slippage;
    uint256 targetLTV;
}

/// @title Leveraged maticX yield adapter
/// @author Vaultcraft
/// @notice ERC4626 wrapper for leveraging maticX yield
/// @dev The strategy takes MaticX and deposits it into a lending protocol (aave).
/// Then it borrows Matic, swap for MaticX and redeposits it
contract MaticXLooper is BaseStrategy, IFlashLoanReceiver {
    // using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // address of the aave/spark router
    ILendingPool public lendingPool;
    IPoolAddressesProvider public poolAddressesProvider;
    IAaveIncentives public aaveIncentives;

    IWMatic public constant wMatic =
        IWMatic(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); // wmatic borrow asset
    IMaticXPool public maticXPool; // stader pool for wrapping - converting

    IERC20 public debtToken; // aave wmatic debt token
    IERC20 public interestToken; // aave MaticX

    IBalancerVault public balancerVault;
    bytes32 public balancerPoolId;

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
    function initialize(
        address asset_,
        address owner_,
        bool autoDeposit_,
        bytes memory strategyInitData_
    ) public initializer {
        __BaseStrategy_init(asset_, owner_, autoDeposit_);

        LooperInitValues memory initValues = abi.decode(
            strategyInitData_,
            (LooperInitValues)
        );

        maticXPool = IMaticXPool(initValues.maticXPool);

        // retrieve and set maticX aToken, lending pool
        (address _aToken, , ) = IProtocolDataProvider(
            initValues.aaveDataProvider
        ).getReserveTokensAddresses(asset_);
        interestToken = IERC20(_aToken);
        lendingPool = ILendingPool(IAToken(_aToken).POOL());
        aaveIncentives = IAaveIncentives(
            IAToken(_aToken).getIncentivesController()
        );

        // set efficiency mode - Matic correlated
        lendingPool.setUserEMode(uint8(2));

        // get protocol LTV
        DataTypes.EModeData memory emodeData = lendingPool.getEModeCategoryData(
            uint8(1)
        );
        protocolMaxLTV = uint256(emodeData.maxLTV) * 1e14; // make it 18 decimals to compare;

        // check ltv init values are correct
        _verifyLTV(initValues.targetLTV, initValues.maxLTV, protocolMaxLTV);

        targetLTV = initValues.targetLTV;
        maxLTV = initValues.maxLTV;

        poolAddressesProvider = IPoolAddressesProvider(
            initValues.poolAddressesProvider
        );

        // retrieve and set wMatic variable debt token
        (, , address _variableDebtToken) = IProtocolDataProvider(
            initValues.aaveDataProvider
        ).getReserveTokensAddresses(address(wMatic));

        debtToken = IERC20(_variableDebtToken); // variable debt wMatic token

        _name = string.concat(
            "VaultCraft Leveraged ",
            IERC20Metadata(asset_).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(asset_).symbol());

        // approve aave router to pull maticX
        IERC20(asset_).approve(address(lendingPool), type(uint256).max);

        // approve aave pool to pull wMatic as part of a flash loan
        IERC20(address(wMatic)).approve(
            address(lendingPool),
            type(uint256).max
        );

        balancerPoolId = initValues.poolId;

        // approve balancer vault to trade MaticX
        balancerVault = IBalancerVault(initValues.balancerVault);
        IERC20(asset_).approve(address(balancerVault), type(uint256).max);

        // set slippage
        if (initValues.slippage > 2e17) {
            revert InvalidSlippage(initValues.slippage, 2e17);
        }

        slippage = initValues.slippage;
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
        (uint256 debt, , ) = maticXPool.convertMaticToMaticX(
            debtToken.balanceOf(address(this))
        ); // matic debt converted in maticX amount
        uint256 collateral = interestToken.balanceOf(address(this)); // maticX collateral

        if (debt >= collateral) return 0;

        uint256 total = collateral;
        if (debt > 0) {
            total -= debt;

            // if there's debt, apply slippage to repay it
            uint256 slippageDebt = debt.mulDiv(
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

    /// @notice The token rewarded if the aave liquidity mining is active
    function rewardTokens() external view override returns (address[] memory) {
        return aaveIncentives.getRewardsByAsset(asset());
    }

    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        revert();
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

        (
            bool isWithdraw,
            bool isFullWithdraw,
            uint256 assetsToWithdraw,
            uint256 depositAmount
        ) = abi.decode(params, (bool, bool, uint256, uint256));

        if (isWithdraw) {
            // flash loan is to repay Matic debt as part of a withdrawal
            uint256 flashLoanDebt = amounts[0] + premiums[0];

            // repay cdp wMatic debt
            lendingPool.repay(address(wMatic), amounts[0], 2, address(this));

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

    /// @notice Deposit maticX into lending protocol
    function _protocolDeposit(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        // deposit maticX into aave - receive aToken here
        lendingPool.supply(asset(), assets, address(this), 0);
    }

    /// @notice repay part of the vault debt and withdraw maticX
    function _protocolWithdraw(
        uint256 assets,
        uint256,
        bytes memory
    ) internal override {
        (, uint256 currentDebt, uint256 currentCollateral) = _getCurrentLTV();
        (uint256 maticAssetsValue, , ) = maticXPool.convertMaticXToMatic(
            assets
        );

        bool isFullWithdraw;
        uint256 ratioDebtToRepay;

        {
            uint256 debtSlippage = currentDebt.mulDiv(
                slippage,
                1e18,
                Math.Rounding.Ceil
            );

            // find the % of debt to repay as the % of collateral being withdrawn
            ratioDebtToRepay = maticAssetsValue.mulDiv(
                1e18,
                (currentCollateral - currentDebt - debtSlippage),
                Math.Rounding.Floor
            );

            isFullWithdraw =
                assets == _totalAssets() ||
                ratioDebtToRepay >= 1e18;
        }

        // get the LTV we would have without repaying debt
        uint256 futureLTV = isFullWithdraw
            ? type(uint256).max
            : currentDebt.mulDiv(
                1e18,
                (currentCollateral - maticAssetsValue),
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
                : currentDebt.mulDiv(
                    ratioDebtToRepay,
                    1e18,
                    Math.Rounding.Floor
                );

            // flash loan debtToRepay - mode 0 - flash loan is repaid at the end
            _flashLoanMatic(debtToRepay, 0, assets, 0, isFullWithdraw);
        }

        // reverts if LTV got above max
        _assertHealthyLTV();
    }

    // deposit back into the protocol
    // either from flash loan or simply Matic dust held by the adapter
    function _redepositAsset(
        uint256 borrowAmount,
        uint256 depositAmount
    ) internal {
        address maticX = asset();

        if (borrowAmount > 0) {
            // unwrap into Matic the flash loaned amount
            wMatic.withdraw(borrowAmount);
        }

        // stake borrowed matic and receive maticX
        maticXPool.swapMaticForMaticXViaInstantPool{value: depositAmount}();

        // get maticX balance after staking
        // may include eventual maticX dust held by contract somehow
        // in that case it will just add more collateral
        uint256 maticXAmount = IERC20(maticX).balanceOf(address(this));

        // deposit maticX into lending protocol
        _protocolDeposit(maticXAmount, 0, hex"");
    }

    // reduce leverage by withdrawing maticX, swapping to Matic repaying Matic debt
    function _reduceLeverage(
        bool isFullWithdraw,
        uint256 toWithdraw,
        uint256 flashLoanDebt
    ) internal {
        address asset = asset();

        // get flash loan amount converted in maticX
        (uint256 flashLoanMaticXAmount, , ) = maticXPool.convertMaticToMaticX(
            flashLoanDebt
        );

        // get slippage buffer for swapping with flashLoanDebt as minAmountOut
        uint256 maticXBuffer = flashLoanMaticXAmount.mulDiv(
            slippage,
            1e18,
            Math.Rounding.Floor
        );

        // if the withdraw amount with buffers to total assets withdraw all
        if (flashLoanMaticXAmount + maticXBuffer + toWithdraw >= _totalAssets())
            isFullWithdraw = true;

        // withdraw maticX from aave
        if (isFullWithdraw) {
            // withdraw all
            lendingPool.withdraw(asset, type(uint256).max, address(this));
        } else {
            lendingPool.withdraw(
                asset,
                flashLoanMaticXAmount + maticXBuffer + toWithdraw,
                address(this)
            );
        }

        // swap maticX to exact wMatic on Balancer - will be pulled by AAVE pool as flash loan repayment
        _swapToWMatic(
            flashLoanMaticXAmount + maticXBuffer,
            flashLoanDebt,
            asset
        );
    }

    // returns current loan to value, debt and collateral (token) amounts
    function _getCurrentLTV()
        internal
        view
        returns (uint256 loanToValue, uint256 debt, uint256 collateral)
    {
        debt = debtToken.balanceOf(address(this)); // wmatic DEBT
        (collateral, , ) = maticXPool.convertMaticXToMatic(
            interestToken.balanceOf(address(this))
        ); // converted into Matic amount;

        (debt == 0 || collateral == 0) ? loanToValue = 0 : loanToValue = debt
            .mulDiv(1e18, collateral, Math.Rounding.Ceil);
    }

    // reverts if targetLTV < maxLTV < protocolLTV is not satisfied
    function _verifyLTV(
        uint256 _targetLTV,
        uint256 _maxLTV,
        uint256 _protocolLTV
    ) internal pure {
        if (_targetLTV >= _maxLTV) {
            revert InvalidLTV(_targetLTV, _maxLTV, _protocolLTV);
        }
        if (_maxLTV >= _protocolLTV) {
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

    // borrow wMatic from lending protocol
    // interestRateMode = 2 -> flash loan matic and deposit into cdp, don't repay
    // interestRateMode = 0 -> flash loan matic to repay cdp, have to repay flash loan at the end
    function _flashLoanMatic(
        uint256 borrowAmount,
        uint256 depositAmount,
        uint256 assetsToWithdraw,
        uint256 interestRateMode,
        bool isFullWithdraw
    ) internal {
        uint256 depositAmount_ = depositAmount; // avoids stack too deep

        address[] memory assets = new address[](1);
        assets[0] = address(wMatic);

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
            abi.encode(
                interestRateMode == 0 ? true : false,
                isFullWithdraw,
                assetsToWithdraw,
                depositAmount_
            ),
            0
        );
    }

    // swaps MaticX to exact wMatic
    function _swapToWMatic(
        uint256 maxAmountIn,
        uint256 exactAmountOut,
        address asset
    ) internal {
        SingleSwap memory swap = SingleSwap(
            balancerPoolId,
            SwapKind.GIVEN_OUT,
            asset,
            address(wMatic),
            exactAmountOut,
            hex""
        );

        balancerVault.swap(
            swap,
            FundManagement(address(this), false, payable(address(this)), false),
            maxAmountIn,
            block.timestamp
        );
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim additional rewards given that it's active.
    function claim() internal override returns (bool success) {
        if (address(aaveIncentives) == address(0)) return false;

        address[] memory _assets = new address[](1);
        _assets[0] = address(interestToken);

        try
            aaveIncentives.claimAllRewardsOnBehalf(
                _assets,
                address(this),
                address(this)
            )
        {
            success = true;
        } catch {}
    }

    function setHarvestValues(
        address newBalancerVault,
        bytes32 newBalancerPoolId
    ) external onlyOwner {
        if (newBalancerVault != address(balancerVault)) {
            address asset_ = asset();

            // reset old pool
            IERC20(asset_).approve(address(balancerVault), 0);

            // set and approve new one
            balancerVault = IBalancerVault(newBalancerVault);
            IERC20(asset_).approve(newBalancerVault, type(uint256).max);
        }

        if (newBalancerPoolId != balancerPoolId)
            balancerPoolId = newBalancerPoolId;
    }

    function harvest(bytes memory data) external override onlyKeeperOrOwner {
        claim();

        address[] memory _rewardTokens = aaveIncentives.getRewardsByAsset(
            asset()
        );

        for (uint256 i; i < _rewardTokens.length; i++) {
            uint256 balance = IERC20(_rewardTokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(_rewardTokens[i]).transfer(msg.sender, balance);
            }
        }

        uint256 assetAmount = abi.decode(data, (uint256));

        if (assetAmount == 0) revert ZeroAmount();

        IERC20(asset()).transferFrom(msg.sender, address(this), assetAmount);

        _protocolDeposit(assetAmount, 0, bytes(""));

        emit Harvested();
    }

    // amount of wMatic to borrow OR amount of wMatic to repay (converted into maticX amount internally)
    function adjustLeverage() public {
        // get vault current leverage : debt/collateral
        (
            uint256 currentLTV,
            uint256 currentDebt,
            uint256 currentCollateral
        ) = _getCurrentLTV();

        // de-leverage if vault LTV is higher than target
        if (currentLTV > targetLTV) {
            uint256 amountMatic = (currentDebt -
                (
                    targetLTV.mulDiv(
                        (currentCollateral),
                        1e18,
                        Math.Rounding.Floor
                    )
                )).mulDiv(1e18, (1e18 - targetLTV), Math.Rounding.Ceil);

            // flash loan matic to repay part of the debt
            _flashLoanMatic(amountMatic, 0, 0, 0, false);
        } else {
            uint256 amountMatic = (targetLTV.mulDiv(
                currentCollateral,
                1e18,
                Math.Rounding.Ceil
            ) - currentDebt).mulDiv(
                    1e18,
                    (1e18 - targetLTV),
                    Math.Rounding.Ceil
                );

            uint256 dustBalance = address(this).balance;
            if (dustBalance < amountMatic) {
                // flashloan but use eventual Matic dust remained in the contract as well
                uint256 borrowAmount = amountMatic - dustBalance;

                // flash loan wMatic from lending protocol and add to cdp
                _flashLoanMatic(borrowAmount, amountMatic, 0, 2, false);
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
        // send matic dust to recipient
        uint256 maticBalance = address(this).balance;
        if (maticBalance > 0) {
            (bool sent,) = address(recipient).call{value: address(this).balance}("");
            require(sent, "Failed to send Matic");
        }

        // send maticX 
        uint256 maticXBalance = IERC20(asset()).balanceOf(address(this));
        if(totalSupply() == 0 && maticXBalance > 0) {
            IERC20(asset()).transfer(recipient, maticXBalance);
        }
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
