// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../../base/BaseAdapter.sol";
import {ICToken, ICometRewarder, IGovernor, IAdmin, ICometConfigurator} from "./ICompoundV3.sol";

contract CompoundV3Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Compound cToken contract
    ICToken public cToken;

    /// @notice The Compound Comet rewarder contract.
    ICometRewarder public cometRewarder;

    /// @notice The Compound Comet configurator contract.
    ICometConfigurator public cometConfigurator;

    error InvalidAsset(address asset);

    function __CompoundV3Adapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        __BaseAdapter_init(_adapterConfig);

        (address _cToken, address _cometRewarder) = abi.decode(
            _protocolConfig.protocolInitData,
            (address, address)
        );

        cToken = ICToken(_cToken);
        cometRewarder = ICometRewarder(_cometRewarder);
        cometConfigurator = ICometConfigurator(_protocolConfig.registry);

        address configuratorBaseToken = cometConfigurator
            .getConfiguration(address(cToken))
            .baseToken;
        if (address(_adapterConfig.underlying) != configuratorBaseToken)
            revert InvalidAsset(configuratorBaseToken);

        _adapterConfig.underlying.approve(address(cToken), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return cToken.balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/
    error SupplyPaused();

    function _deposit(uint256 amount) internal override {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        if (cToken.isSupplyPaused() == true) revert SupplyPaused();
        cToken.supply(address(underlying), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    error WithdrawPaused();

    function _withdraw(uint256 amount, address receiver) internal override {
        _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        if (cToken.isWithdrawPaused() == true) revert WithdrawPaused();
        cToken.withdraw(address(underlying), amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        try
            cometRewarder.claim(address(cToken), address(this), true)
        {} catch {}
    }
}
