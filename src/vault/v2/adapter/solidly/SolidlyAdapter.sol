// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IGauge, ILpToken} from "./ISolidly.sol";
import {IPermissionRegistry} from "../../../../interfaces/vault/IPermissionRegistry.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


contract GmdAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice The Solidly contract
    IGauge public gauge;

    error InvalidAsset();
    error LpTokenSupported();
    error NotEndorsed(address gauge);


    function __GmdAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if(!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        address _gauge = abi.decode(_protocolConfig.protocolInitData, (address));
        if (!IPermissionRegistry(_protocolConfig.registry).endorsed(_gauge))
            revert NotEndorsed(_gauge);

        gauge = IGauge(_gauge);
        if (gauge.stake() != address (lpToken)) revert InvalidAsset();
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



    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
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


    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawLP(amount);
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

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Claim rewards from the Solidly gauge
    function _claim() internal override {
        try gauge.getReward(address(this), _getRewardTokens()) {
        } catch {}
    }

    function _getRewardTokens() internal view returns(address[] memory) {
        address[] memory _rewardTokens = new address[](3);
        _rewardTokens[0] = address(rewardTokens[0]);
        _rewardTokens[1] = address(rewardTokens[1]);
        _rewardTokens[2] = address(rewardTokens[2]);

        return _rewardTokens;
    }
}
