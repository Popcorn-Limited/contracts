// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IAlpacaLendV1Vault} from "./IAlpacaLendV1.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract AlpacaLendV1Adapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The Alpaca Lend V1 Vault contract
    IAlpacaLendV1Vault public alpacaVault;

    error NotEndorsed();
    error InvalidAsset();

    function __AlpacaLendV1Adapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        address _vault = abi.decode(_protocolConfig.protocolInitData, (address));

        //TODO: uncomment when across PR is merged
//        if (!IPermissionRegistry(registry).endorsed(_vault))
//            revert NotEndorsed();

        alpacaVault = IAlpacaLendV1Vault(_vault);

        if (alpacaVault.token() != address(underlying)) revert InvalidAsset();

        _adapterConfig.underlying.approve(address(alpacaVault), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return (alpacaVault.balanceOf(address(this)) * alpacaVault.totalToken())
                / alpacaVault.totalSupply();
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
        alpacaVault.deposit(amount);
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
        uint256 alpacaShares = convertToUnderlyingShares(0, amount);
        alpacaVault.withdraw(alpacaShares);
    }

    /// @notice The amount of alapacaV1 shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view returns (uint256) {
        return shares.mulDiv(
            alpacaVault.totalSupply(),
            alpacaVault.totalToken(),
            Math.Rounding.Up
        );
    }
}
