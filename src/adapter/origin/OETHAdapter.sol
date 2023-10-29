// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20, AdapterConfig, IERC4626} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract OETHAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice The wrapped oToken contract.
    IERC4626 public constant wOETH = IERC4626(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);

    error InvalidAsset();
    error LpTokenNotSupported();

    function __OriginAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        if (wOETH.asset() != address(underlying))
            revert InvalidAsset();

        _adapterConfig.underlying.approve(address(wOETH), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return wOETH.convertToAssets(wOETH.balanceOf(address(this)));
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        wOETH.deposit(amount, address(this));
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
        wOETH.withdraw(amount, address(this), address(this));
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    function _claim() internal pure override {}
}
