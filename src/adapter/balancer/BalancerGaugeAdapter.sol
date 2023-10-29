// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {IGauge, IMinter, IGaugeController} from "./IBalancer.sol";

contract BalancerGaugeAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    IGaugeController public constant gaugeController = IGaugeController(0xC128468b7Ce63eA702C1f104D55A2566b13D3ABD);
    /// @notice The balancer minter contract
    IMinter public constant balMinter = IMinter(0x239e55F427D44C3cc793f49bFB507ebe76638a2b);

    /// @notice The balancer gauge contract
    IGauge public gauge;

    error InvalidGauge();
    error LpTokenSupported();

    function __BalanceGaugeAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (!_adapterConfig.useLpToken) revert LpTokenSupported();
        __BaseAdapter_init(_adapterConfig);

        address _gauge = abi.decode(
            _adapterConfig.protocolData,
            (address)
        );
        if (!gaugeController.gauge_exists(_gauge)) {
            revert InvalidGauge();
        }
        gauge = IGauge(_gauge);

        _adapterConfig.underlying.approve(address(gauge), type(uint256).max);
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

    function _totalUnderlying() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        underlying.safeTransferFrom(caller, address(this), amount);
        _depositLP(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
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
        lpToken.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawLP(uint256 amount) internal override {
        gauge.withdraw(amount, false);
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
        try balMinter.mint(address(gauge)) {} catch {}
    }
}
