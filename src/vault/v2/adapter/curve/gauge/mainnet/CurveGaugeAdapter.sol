// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IGauge, IMinter, IGaugeController} from "../../ICurve.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";


contract CurveGaugeAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Curve Gauge contract
    IGauge public gauge;

    /// @notice The Curve Gauge contract
    IMinter public minter;

    address public crv;

    error InvalidToken();
    error LpTokenSupported();

    function __CurveGaugeAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        uint256 _gaugeId = abi.decode(_protocolConfig.protocolInitData, (uint256));
        minter = IMinter(_protocolConfig.registry);
        gauge = IGauge(IGaugeController(minter.controller()).gauges(_gaugeId));

        crv = minter.token();
        if (gauge.lp_token() != address (lpToken)) revert InvalidToken();

        _adapterConfig.lpToken.approve(address(gauge), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalLP() internal view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount) internal override {
        _depositLP(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositLP(uint256 amount) internal override {
        gauge.deposit(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawLP(amount);
        lpToken.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        gauge.withdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try minter.mint(address(gauge)) {} catch {}
    }
}
