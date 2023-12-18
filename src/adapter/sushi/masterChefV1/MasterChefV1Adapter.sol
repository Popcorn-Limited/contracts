// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IMasterChefV1} from "./IMasterChefV1.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract MasterChefV1Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    // @notice The MasterChef contract
    IMasterChefV1 public masterChef = IMasterChefV1(0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd);

    // @notice The pool ID
    uint256 public pid;

    error InvalidAsset();
    error LpTokenSupported();

    function __MasterChefV1Adapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        (uint256 _pid) = abi.decode(
            _adapterConfig.protocolData,
            (uint256)
        );

        pid = _pid;
        IMasterChefV1.PoolInfo memory pool = masterChef.poolInfo(_pid);

        if (pool.lpToken != address(lpToken)) revert InvalidAsset();
        _adapterConfig.lpToken.approve(address(masterChef), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalLP() internal view override returns (uint256) {
        IMasterChefV1.UserInfo memory user = masterChef.userInfo(
            pid,
            address(this)
        );
        return user.amount;
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

    function _depositLP(uint256 amount) internal override {
        masterChef.deposit(pid, amount);
    }

    function _depositUnderlying(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawLP(amount);
        lpToken.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        masterChef.withdraw(pid, amount);
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
        try masterChef.deposit(pid, 0) {} catch {}
    }
}
