// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {IMetaPool} from "./IMetaPool.sol";
import {IPermissionRegistry} from "../../base/interfaces/IPermissionRegistry.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig, IERC20Metadata} from "../../base/BaseAdapter.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract MetaPoolAdapter is BaseAdapter {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 internal constant stNearDecimals = 24;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    IMetaPool public iPool;
    IERC20Metadata public stNear;
    IERC20Metadata public wNear;

    error NotValidCDO(address cdo);
    error PausedCDO(address cdo);
    error NotValidAsset(address asset);

    error AssetMismatch();
    error LpTokenSupported();

    function __MetaPoolAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        iPool = IMetaPool(_protocolConfig.registry);
        if (address(iPool.wNear()) != address(lpToken))
            revert NotValidAsset(address(lpToken));

        stNear = iPool.stNear();
        wNear = iPool.wNear();

        IERC20(stNear).safeApprove(_protocolConfig.registry, type(uint256).max);
        _adapterConfig.lpToken.approve(
            address(_protocolConfig.registry),
            type(uint256).max
        );
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
        return
            (stNear.balanceOf(address(this)) *
                (BPS_DENOMINATOR - iPool.wNearSwapFee()) *
                iPool.stNearPrice()) /
            BPS_DENOMINATOR /
            (10 ** stNearDecimals);
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
        iPool.swapwNEARForstNEAR(amount);
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
        iPool.swapstNEARForwNEAR(convertToUnderlyingShares(amount));
    }

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalLP();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    stNear.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }
}
