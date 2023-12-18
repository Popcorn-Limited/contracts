// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {IGauge, ILpToken} from "./IVelodrome.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IPermissionRegistry} from "../../base/interfaces/IPermissionRegistry.sol";

contract VelodromeAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //// @notice The Velodrome contract
    IGauge public gauge;

    error InvalidAsset();
    error InvalidGauge();
    error LpTokenSupported();

    function __VelodromeAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        (address permissionRegistry, address _gauge) = abi.decode(
            _adapterConfig.protocolData,
            (address, address)
        );

        if (!IPermissionRegistry(permissionRegistry).endorsed(_gauge)) {
            revert InvalidGauge();
        }

        gauge = IGauge(_gauge);
        if (gauge.stake() != address(lpToken)) revert InvalidAsset();

        _adapterConfig.lpToken.approve(address(_gauge), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of lptoken assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert
     * lpToken balance into lpToken balance
     */
    function _totalLP() internal view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _totalUnderlying() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        lpToken.safeTransferFrom(caller, address(this), amount);
        _depositLP(amount);
    }

    /**
     * @notice Deposits lpToken asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before
     * depositing others might use the lpToken directly
     **/
    function _depositLP(uint256 amount) internal override {
        gauge.deposit(amount);
    }

    function _depositUnderlying(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawLP(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws lpToken asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing others
     * might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        gauge.withdraw(amount);
    }

    function _withdrawUnderlying(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try gauge.getReward(address(this)) {} catch {}
    }
}
