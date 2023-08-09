// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20} from "../base/BaseAdapter.sol";
import {ILendingPool, IAaveIncentives, IAToken, IProtocolDataProvider} from "../../adapter/aave/aaveV3/IAaveV3.sol";

contract AaveV3Adapter is BaseAdapter {
    /// @notice The Aave aToken contract
    IAToken public aToken;

    /// @notice The Aave liquidity mining contract
    IAaveIncentives public aaveIncentives;

    /// @notice Check to see if Aave liquidity mining is active
    bool public isActiveIncentives;

    /// @notice The Aave LendingPool contract
    ILendingPool public lendingPool;

    function __AaveV3Adapter_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        address _vault,
        bool _useLpToken,
        bytes memory adapterInitData,
        address aaveDataProvider,
        bytes memory
    ) internal onlyInitializing {
        __BaseAdapter_init(_underlying, _lpToken, _vault, _useLpToken);

        (address _aToken, , ) = IProtocolDataProvider(aaveDataProvider)
            .getReserveTokensAddresses(address(_underlying));
        aToken = IAToken(_aToken);

        lendingPool = ILendingPool(aToken.POOL());
        aaveIncentives = IAaveIncentives(aToken.getIncentivesController());

        _underlying.approve(address(lendingPool), type(uint256).max);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        lendingPool.supply(address(underlying), amount, address(this), 0);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        lendingPool.withdraw(address(underlying), amount, address(this));
    }

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /**
     * @notice Claims rewards
     */
    function _claimRewards() internal override {
        if (address(aaveIncentives) == address(0)) return false;

        address[] memory _assets = new address[](1);
        _assets[0] = address(aToken);

        try
            aaveIncentives.claimAllRewardsOnBehalf(
                _assets,
                address(this),
                address(this)
            )
        {} catch {}
    }
}
