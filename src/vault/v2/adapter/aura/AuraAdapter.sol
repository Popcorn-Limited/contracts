// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {IAuraBooster, IAuraRewards, IAuraStaking} from "./IAura.sol";

contract AuraAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Aura booster contract
    IAuraBooster public auraBooster;

    /// @notice The reward contract for Aura gauge
    IAuraRewards public auraRewards;

    /// @notice The pool ID
    uint256 public pid;

    function __AuraAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        pid = abi.decode(_protocolConfig.protocolInitData, (uint256));
        auraBooster = IAuraBooster(_protocolConfig.registry);

        (address balancerLpToken, , , address _auraRewards, , ) = auraBooster
            .poolInfo(pid);
        auraRewards = IAuraRewards(_auraRewards);

        _adapterConfig.lpToken.approve(address(auraBooster), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalLP() internal view override returns (uint256) {
        return auraRewards.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        _depositLP(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositLP(uint256 amount) internal override {
        auraBooster.deposit(pid, amount, true);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount) internal override {
        _withdrawLP(amount);
        lpToken.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        auraRewards.withdrawAndUnwrap(amount, true);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try auraRewards.getReward() {} catch {}
    }
}
