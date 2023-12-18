// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IGauge, ILpToken} from "./ISolidly.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IPermissionRegistry} from "../../base/interfaces/IPermissionRegistry.sol";

contract GmdAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice The Solidly contract
    IGauge public gauge;

    error NotEndorsed(address _gauge);
    error InvalidAsset();
    error LpTokenSupported();

    function __GmdAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        address _gauge = abi.decode(_adapterConfig.protocolData, (address));

        // @dev permissionRegistry of eth
        // @dev change the registry address depending on the deployed chain
        if (
            !IPermissionRegistry(0x7a33b5b57C8b235A3519e6C010027c5cebB15CB4)
                .endorsed(_gauge)
        ) revert NotEndorsed(_gauge);

        // the gauge is valid
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
        gauge.depositAndOptIn(amount, 0, _getRewardTokens());
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
    /// @notice Claim rewards from the Solidly gauge
    function _claim() internal override {
        try gauge.getReward(address(this), _getRewardTokens()) {} catch {}
    }

    /**
     * @notice Gets all the reward tokens for a protocol
     * @dev This function converts all reward token types from IERC20[] to address[]
     **/
    function _getRewardTokens()
        internal
        view
        virtual
        returns (address[] memory)
    {
        uint256 len = rewardTokens.length;
        address[] memory _rewardTokens = new address[](len);
        for (uint256 i = 0; i < len; ) {
            _rewardTokens[i] = address(rewardTokens[i]);
            unchecked {
                i++;
            }
        }

        return _rewardTokens;
    }
}
