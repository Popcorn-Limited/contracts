// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IIdleCDO, IRegistry} from "../IIdle.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract IdleJuniorAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IIdleCDO public cdo;

    error LpTokenNotSupported();
    error PausedCDO(address cdo);
    error NotValidCDO(address cdo);
    error NotValidAsset(address asset);

    function __IdleJuniorAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        IRegistry _registry = IRegistry(0x84FDeE80F18957A041354E99C7eB407467D94d8E);
        address _cdo = abi.decode(_adapterConfig.protocolData, (address));

        if (!_registry.isValidCdo(_cdo)) revert NotValidCDO(_cdo);
        if (IIdleCDO(_cdo).paused()) revert PausedCDO(_cdo);
        if (IIdleCDO(_cdo).token() != address(underlying))
            revert NotValidAsset(address(underlying));

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
        address tranche = cdo.BBTranche();
        return
            IERC20(tranche).balanceOf(address(this)).mulDiv(
                cdo.tranchePrice(tranche),
                cdo.ONE_TRANCHE_TOKEN(),
                Math.Rounding.Down
            );
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
        cdo.depositBBRef(amount, FEE_RECIPIENT);
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
        cdo.withdrawBB(convertToUnderlyingShares(amount));
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 balance = IERC20(cdo.BBTranche()).balanceOf(address(this));
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(balance, supply, Math.Rounding.Up);
    }

    /// @dev no rewards on idle
    function _claim() internal override {}
}
