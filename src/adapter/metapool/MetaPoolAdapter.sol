// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {IMetaPool} from "./IMetaPool.sol";
import {IPermissionRegistry} from "../../base/interfaces/IPermissionRegistry.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig, IERC20Metadata} from "../../base/BaseAdapter.sol";
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

    // TODO: main liquidity seems to be on NEAR. Do we even use this?

    function __MetaPoolAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        iPool = abi.decode(_adapterConfig.protocolData, (IMetaPool));
        if (address(iPool.wNear()) != address(lpToken))
            revert NotValidAsset(address(lpToken));

        stNear = iPool.stNear();
        wNear = iPool.wNear();

        IERC20(stNear).safeApprove(address(iPool), type(uint256).max);
        _adapterConfig.lpToken.approve(
            address(address(iPool)),
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
        iPool.swapwNEARForstNEAR(amount);
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
        iPool.swapstNEARForwNEAR(convertToUnderlyingShares(amount));
    }

    function _withdrawUnderlying(uint) internal pure override {
        revert("NO");
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

    function _claim() internal pure override {}
}
