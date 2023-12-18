// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IAlpacaLendV1Vault} from "./IAlpacaLendV1.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IPermissionRegistry} from "../../../base/interfaces/IPermissionRegistry.sol";

contract AlpacaLendV1Adapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Alpaca Lend V1 Vault contract
    IAlpacaLendV1Vault public alpacaVault;

    error NotEndorsed(address vault);
    error InvalidAsset();
    error LpTokenNotSupported();

    function __AlpacaLendV1Adapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        address _vault = abi.decode(_adapterConfig.protocolData, (address));

        // @dev permissionRegistry of bsc
        // @dev change the registry address depending on the deployed chain
        if (
            !IPermissionRegistry(0x8c76AA6B65D0619042EAd6DF748f782c89a06357)
                .endorsed(_vault)
        ) revert NotEndorsed(_vault);

        alpacaVault = IAlpacaLendV1Vault(_vault);

        if (alpacaVault.token() != address(underlying)) revert InvalidAsset();

        _adapterConfig.underlying.approve(
            address(alpacaVault),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return
            (alpacaVault.balanceOf(address(this)) * alpacaVault.totalToken()) /
            alpacaVault.totalSupply();
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
        alpacaVault.deposit(amount);
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
        alpacaVault.withdraw(convertToUnderlyingShares(0, amount));
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    /// @notice The amount of alapacaV1 shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view returns (uint256) {
        return
            shares.mulDiv(
                alpacaVault.totalSupply(),
                alpacaVault.totalToken(),
                Math.Rounding.Up
            );
    }

    /// @dev no rewards on alpacalend v1
    function _claim() internal pure override {}
}
