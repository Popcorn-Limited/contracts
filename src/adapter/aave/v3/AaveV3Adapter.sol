// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {ILendingPool, IAaveIncentives, IAToken, IProtocolDataProvider} from "./IAaveV3.sol";

contract AaveV3Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Aave aToken contract
    IAToken public aToken;

    /// @notice The Aave liquidity mining contract
    IAaveIncentives public constant aaveIncentives = IAaveIncentives(0x8164Cc65827dcFe994AB23944CBC90e0aa80bFcb);

    /// @notice The Aave LendingPool contract
    ILendingPool public constant lendingPool = ILendingPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    IProtocolDataProvider public constant dataProvider = IProtocolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);

    error LpTokenNotSupported();

    function __AaveV3Adapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_adapterConfig);

        (address _aToken, , ) = dataProvider.getReserveTokensAddresses(address(_adapterConfig.underlying));
        aToken = IAToken(_aToken);

        _adapterConfig.underlying.approve(
            address(lendingPool),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        if (caller != address(this))
            underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        lendingPool.supply(address(underlying), amount, address(this), 0);
    }

    function _depositLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        lendingPool.withdraw(address(underlying), amount, address(this));
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        // see https://docs.aave.com/developers/whats-new/multiple-rewards-and-claim#multiple-rewards-and-claim
        if (aaveIncentives.getRewardsByAsset(address(aToken)).length == 0) {
            return;
        }

        address[] memory _assets = new address[](1);
        _assets[0] = address(aToken);

        try
            aaveIncentives.claimAllRewardsToSelf(_assets) returns (address[] memory, uint[] memory)
        {} catch {}
    }
}
