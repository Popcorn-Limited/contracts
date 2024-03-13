// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20} from "../../abstracts/AdapterBase.sol";
import {
    ICreditFacadeV3, ICreditManagerV3, MultiCall, ICreditFacadeV3Multicall, CollateralDebtData, CollateralCalcTask
} from "./IGearboxV3.sol";

/**
 * @title   Gearbox Passive Pool Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Gearbox's passive pools.
 *
 * An ERC4626 compliant Wrapper for https://github.com/Gearbox-protocol/core-v2/blob/main/contracts/pool/PoolService.sol.
 * Allows wrapping Passive pools.
 */
contract GearboxLeverage is AdapterBase {
    using SafeERC20 for IERC20;

    string internal _name;
    string internal _symbol;

    uint256 public leverageRatio;
    address public creditAccount;
    ICreditFacadeV3 public creditFacade;
    ICreditManagerV3 public creditManager;

    /*//////////////////////////////////////////////////////////////
                                INITIALIZATION
   //////////////////////////////////////////////////////////////*/

    error WrongPool();
    error CreditAccountLiquidatable();

    /**
     * @notice Initialize a new Gearbox Passive Pool Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param gearboxInitData Encoded data for the Lido adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address,
        bytes memory gearboxInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        (address _creditFacade, address _creditManager) = abi.decode(
            gearboxInitData,
            (address, address)
        );

        creditFacade = ICreditFacadeV3(_creditFacade);
        creditManager = ICreditManagerV3(_creditManager);
        creditAccount = ICreditFacadeV3(_creditFacade).openCreditAccount(address(this), new MultiCall[](0), 0);

        (   uint256 debt,
            uint256 cumulativeIndexLastUpdate,
            uint128 cumulativeQuotaInterest,
            uint128 quotaFees,
            uint256 enabledTokensMask,
            uint16 flags,
            uint64 lastDebtUpdate,
            address borrower
        ) = creditManager.creditAccountInfo(creditAccount);

        _name = string.concat(
            "VaultCraft GearboxLeverage ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-gl-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(_creditManager, type(uint256).max);
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

    function maxWithdraw(
        address owner
    ) public view override returns (uint256) {
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
        if(_creditAccountIsLiquidatable()){
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

    function setHarvestValues(
        uint256 _leverageRatio
    ) public onlyOwner {
        leverageRatio = _leverageRatio;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPERS
    //////////////////////////////////////////////////////////////*/

    function _calculateLeverageRatio() internal view returns (uint256){
        CollateralDebtData memory collateralDebtData = _getCreditAccountData();
        return (collateralDebtData.totalValue + collateralDebtData.debt)/collateralDebtData.totalValue;
    }

    function _reduceDebtLevel(uint256 amount) internal {
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(ICreditFacadeV3Multicall.decreaseDebt, (amount))
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _increaseDebtLevel(uint256 amount) internal {
        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeCall(ICreditFacadeV3Multicall.increaseDebt, (amount))
        });

        creditFacade.multicall(creditAccount, calls);
    }

    function _getCreditAccountData() internal view returns (CollateralDebtData memory){
        return ICreditManagerV3(creditFacade.creditManager()).calcDebtAndCollateral(
            creditAccount, CollateralCalcTask.GENERIC_PARAMS
        );
    }

    function _creditAccountIsLiquidatable() internal view returns(bool) {
        bool _creditFacadeIsExpired;
        uint40 _expirationDate = creditFacade.expirationDate();
        if(!creditFacade.expirable()){
            _creditFacadeIsExpired = false;
        }else {
            _creditFacadeIsExpired = (_expirationDate != 0 && block.timestamp >= _expirationDate);
        }

        CollateralDebtData memory collateralDebtData = _getCreditAccountData();
        bool isUnhealthy = collateralDebtData.twvUSD < collateralDebtData.totalDebtUSD;
        if (collateralDebtData.debt == 0 || !isUnhealthy && !_creditFacadeIsExpired) {
            return false;
        }

        return true;
    }
}
