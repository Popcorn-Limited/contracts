// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IGauge, IMinter, IGaugeController} from "../../ICurve.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../../base/BaseAdapter.sol";
import {Owned} from "../../../../../../utils/Owned.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

struct CurveConfig {
    address gauge;
}

contract CurveGaugeAdapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Curve Gauge contract
    IGauge public gauge;

    /// @notice The Curve Minter contract
    IMinter constant public minter = IMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);


    function __CurveGaugeAdapter_init(
        AdapterConfig memory _adapterConfig,
        CurveConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        gauge = IGauge(_protocolConfig.gauge);

        _adapterConfig.lpToken.approve(_protocolConfig.gauge, type(uint256).max);
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

    function _deposit(uint256 amount, address caller) internal override {
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
        if (!paused()) _withdrawLP(amount);
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


contract CurveGaugeAdapterFactory is Owned {
    /// @dev likelihood of the GaugeController address changing is near zero.
    IGaugeController constant controller = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

    // needs access to TemplateRegistry to register any new copy that's created

    /// @dev the CurveGaugeAdapter contract's address
    address implementation;

    error InvalidToken();
    error LpTokenSupported();

    constructor(address _owner, address _implementation) Owned(_owner) {
        implementation = _implementation;
    }

    function deploy(AdapterConfig calldata adapterConfig, uint gaugeId) external returns (address adapter) {
        if (!adapterConfig.useLpToken) revert LpTokenSupported();

        IGauge gauge = IGauge(controller.gauges(gaugeId));
        if (gauge.lp_token() != address(adapterConfig.lpToken)) revert InvalidToken();
        
        // could add another check to verify that `adapterConfig.rewardTokens` contains CRV.

        CurveConfig memory curveConfig = CurveConfig({
            gauge: address(gauge)
        });

        adapter = Clones.clone(implementation);
        // We'd use the top level strategy contract that exposes a initialize function.
        // Not the case here
        //
        // CurveGaugeAdapter(adapter).initialize(adapterConfig, curveConfig);

        // add to template registry
    }

    function updateImplementation(address newImplementation) external onlyOwner {
        implementation = newImplementation;
    }
}