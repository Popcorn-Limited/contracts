// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {ICToken, ICometRewarder, IGovernor, IAdmin, ICometConfigurator} from "./ICompoundV3.sol";

contract CompoundV3Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Compound cToken contract
    ICToken public cToken;

    /// @notice The Compound Comet rewarder contract.
    ICometRewarder public constant cometRewarder = ICometRewarder(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);

    /// @notice The Compound Comet configurator contract.
    ICometConfigurator public constant cometConfigurator = ICometConfigurator(0x316f9708bB98af7dA9c68C1C3b5e79039cD336E3);

    error InvalidAsset(address asset);
    error LpTokenNotSupported();

    function __CompoundV3Adapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        (address _cToken) = abi.decode(
            _adapterConfig.protocolData,
            (address)
        );

        cToken = ICToken(_cToken);

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

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/
    error SupplyPaused();

    function _deposit(uint256 amount, address caller) internal override {
        underlying.safeTransferFrom(caller, address(this), amount);
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

    function _depositLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/
    error WithdrawPaused();

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawUnderlying(amount);
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

    function _withdrawLP(uint) internal pure override {
        revert("NO");
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
