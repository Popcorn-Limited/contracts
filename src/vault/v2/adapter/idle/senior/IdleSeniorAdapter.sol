// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IIdleCDO, IRegistry} from "../IIdle.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


contract IdleSeniorAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IIdleCDO public cdo;

    error LpTokenNotSupported();
    error PausedCDO(address cdo);
    error NotValidCDO(address cdo);
    error NotValidAsset(address asset);

    function __IdleSeniorAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if(_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        IRegistry _registry = IRegistry(_protocolConfig.registry);
        address _cdo = abi.decode(_protocolConfig.protocolInitData, (address));

        if (!_registry.isValidCdo(_cdo)) revert NotValidCDO(_cdo);
        if (IIdleCDO(_cdo).paused()) revert PausedCDO(_cdo);
        if (IIdleCDO(_cdo).token() != address (underlying)) revert NotValidAsset(address (underlying));

        cdo = IIdleCDO(_cdo);

        _adapterConfig.underlying.approve(address(cdo), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        address tranche = cdo.AATranche();
        return (
            IERC20(tranche).balanceOf(address(this)) * cdo.tranchePrice(tranche)
        ) / cdo.ONE_TRANCHE_TOKEN();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        cdo.depositAARef(amount, FEE_RECIPIENT);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        cdo.withdrawAA(convertToUnderlyingShares(amount));
    }

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 balance = IERC20(cdo.AATranche()).balanceOf(address(this));
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(balance, supply, Math.Rounding.Up);
    }

}
