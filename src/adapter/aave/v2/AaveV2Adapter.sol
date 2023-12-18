// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../../base/BaseAdapter.sol";
import {ILendingPool, IAaveMining, IAToken, IProtocolDataProvider} from "./IAaveV2.sol";

contract AaveV2Adapter is BaseAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Aave aToken contract
    IAToken public aToken;

    /// @notice The Aave liquidity mining contract
    IAaveMining public constant aaveMining =
        IAaveMining(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);

    /// @notice The Aave LendingPool contract
    ILendingPool public constant lendingPool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    IProtocolDataProvider public constant dataProvider =
        IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);

    error LpTokenNotSupported();

    function __AaveV3Adapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_adapterConfig);

        (address _aToken, , ) = dataProvider.getReserveTokensAddresses(
            address(_adapterConfig.underlying)
        );
        aToken = IAToken(_aToken);

        _adapterConfig.underlying.approve(
            address(lendingPool),
            type(uint256).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        if (caller != address(this))
            underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        lendingPool.deposit(address(underlying), amount, address(this), 0);
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
        lendingPool.withdraw(address(underlying), amount, address(this));
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
        address[] memory _assets = new address[](1);
        _assets[0] = address(aToken);

        try
            aaveMining.claimRewards(_assets, type(uint256).max, address(this))
        returns (uint256) {} catch {}
    }
}
