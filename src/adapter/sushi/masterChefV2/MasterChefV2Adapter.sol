// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IMasterChefV2, IRewarder} from "./IMasterChefV2.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract MasterChefV2Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    // @notice The MasterChef contract
    IMasterChefV2 public masterChef;

    // @notice The address of the reward token
    address public rewardsToken;

    // @notice The pool ID
    uint256 public pid;

    error InvalidAsset();
    error LpTokenSupported();

    function __MasterChefV2Adapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        (uint256 _pid, address _rewardsToken) = abi.decode(
            _protocolConfig.protocolInitData,
            (uint256, address)
        );

        pid = _pid;
        rewardsToken = _rewardsToken;
        masterChef = IMasterChefV2(_protocolConfig.registry);
        address _lpToken = masterChef.lpToken(_pid);

        if (_lpToken != address(lpToken)) revert InvalidAsset();
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
        IMasterChefV2.UserInfo memory user = masterChef.userInfo(
            pid,
            address(this)
        );
        return user.amount;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        lpToken.safeTransferFrom(caller, address(this), amount);
        _depositLP(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositLP(uint256 amount) internal override {
        masterChef.deposit(pid, amount, address(this));
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
        masterChef.withdraw(pid, amount, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try masterChef.harvest(pid, address(this)) {} catch {}
    }
}
