// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;
import {BaseStrategy, IERC20, IERC20Metadata, SafeERC20, ERC20, Math} from "../../BaseStrategy.sol";
import {ICreditFacadeV3, ICreditManagerV3, MultiCall, ICreditFacadeV3Multicall, CollateralDebtData, CollateralCalcTask} from "./IGearboxV3.sol";

/**
 * @title   Gearbox Passive Pool Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Gearbox's passive pools.
 *
 * An ERC4626 compliant Wrapper for https://github.com/Gearbox-protocol/core-v2/blob/main/contracts/pool/PoolService.sol.
 * Allows wrapping Passive pools.
 */
abstract contract GearboxLeverageFarm is BaseStrategy {
    using SafeERC20 for IERC20;

    string internal _name;
    string internal _symbol;

    uint256 public targetLeverageRatio;
    address public creditAccount;
    address public strategyAdapter;
    ICreditFacadeV3 public creditFacade;
    ICreditManagerV3 public creditManager;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
   //////////////////////////////////////////////////////////////*/

    error WrongPool();
    error CreditAccountLiquidatable();

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ The underlying asset used for deposit/withdraw and accounting
     * @param owner_ Owner of the contract. Controls management functions.
     * @param autoHarvest_ Controls if the harvest function gets called on deposit/withdrawal
     * @param strategyInitData_ Encoded data for this specific strategy
     */
    function initialize(
        address asset_,
        address owner_,
        bool autoHarvest_,
        bytes memory strategyInitData_
    ) external initializer {
        (
            address _creditFacade,
            address _creditManager,
            address _strategyAdapter
        ) = abi.decode(strategyInitData_, (address, address, address));

        strategyAdapter = _strategyAdapter;
        creditFacade = ICreditFacadeV3(_creditFacade);
        creditManager = ICreditManagerV3(_creditManager);
        creditAccount = ICreditFacadeV3(_creditFacade).openCreditAccount(
            address(this),
            new MultiCall[](0),
            0
        );

        __BaseStrategy_init(asset_, owner_, autoHarvest_);

        IERC20(asset()).approve(_creditManager, type(uint256).max);

        _name = string.concat(
            "VaultCraft GearboxLeverage ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-gl-", IERC20Metadata(asset()).symbol());
    }

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
        return IERC20(asset()).balanceOf(creditAccount); //_getCreditAccountData().totalValue;
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/
    function maxDeposit(address) public view override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 assets, uint256) internal override {
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.addCollateral,
                (asset(), assets)
            )
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _protocolWithdraw(uint256 assets, uint256) internal override {
        if (_creditAccountIsLiquidatable()) {
            revert CreditAccountLiquidatable();
        }

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.withdrawCollateral,
                (asset(), assets, address(this))
            )
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function setTargetLeverageRatio(uint256 _leverageRatio) public onlyOwner {
        targetLeverageRatio = _leverageRatio;
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/
    
    function adjustLeverage(
        uint256 amount,
        bytes memory data
    ) public onlyOwner {
        (
            uint256 currentLeverageRatio,
            CollateralDebtData memory collateralDebtData
        ) = _calculateLeverageRatio();
        uint256 currentCollateral = collateralDebtData.totalValue;
        uint256 currentDebt = collateralDebtData.debt;

        if (currentLeverageRatio > targetLeverageRatio) {
            if (
                Math.ceilDiv(
                    (currentDebt - amount),
                    (currentCollateral - amount)
                ) < targetLeverageRatio
            ) {
                _gearboxStrategyWithdraw(data);
                _reduceLeverage(amount);
            }
        } else {
            if (
                Math.ceilDiv(
                    (currentDebt + amount),
                    (currentCollateral + amount)
                ) < targetLeverageRatio
            ) {
                _increaseLeverage(amount);
                _gearboxStrategyDeposit(data);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HELPERS
    /////////////////////////////////////////////////////////////*/

    function _calculateLeverageRatio()
        internal
        view
        returns (uint256, CollateralDebtData memory)
    {
        CollateralDebtData memory collateralDebtData = _getCreditAccountData();
        return (
            Math.ceilDiv(
                collateralDebtData.debt,
                collateralDebtData.totalValue
            ),
            collateralDebtData
        );
    }

    function _reduceLeverage(uint256 amount) internal {
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.decreaseDebt,
                (amount)
            )
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _increaseLeverage(uint256 amount) internal {
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.increaseDebt,
                (amount)
            )
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _getCreditAccountData()
        internal
        view
        returns (CollateralDebtData memory)
    {
        return
            ICreditManagerV3(creditFacade.creditManager())
                .calcDebtAndCollateral(
                    creditAccount,
                    CollateralCalcTask.GENERIC_PARAMS
                );
    }

    function _creditAccountIsLiquidatable() internal view returns (bool) {
        bool _creditFacadeIsExpired;
        uint40 _expirationDate = creditFacade.expirationDate();
        if (!creditFacade.expirable()) {
            _creditFacadeIsExpired = false;
        } else {
            _creditFacadeIsExpired = (_expirationDate != 0 &&
                block.timestamp >= _expirationDate);
        }

        CollateralDebtData memory collateralDebtData = _getCreditAccountData();
        bool isUnhealthy = collateralDebtData.twvUSD <
            collateralDebtData.totalDebtUSD;
        if (
            collateralDebtData.debt == 0 ||
            (!isUnhealthy && !_creditFacadeIsExpired)
        ) {
            return false;
        }

        return true;
    }

    function _gearboxStrategyDeposit(bytes memory data) internal virtual {}
    function _gearboxStrategyWithdraw(bytes memory data) internal virtual {}
}
