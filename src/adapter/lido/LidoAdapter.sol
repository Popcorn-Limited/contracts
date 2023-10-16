// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {ILido, VaultAPI, ICurveMetapool, IWETH} from "./ILido.sol";

contract LidoAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    int128 private constant WETHID = 0;
    int128 private constant STETHID = 1;

    ICurveMetapool public constant StableSwapSTETH =
        ICurveMetapool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    uint256 public slippage; // 1e18 = 100% slippage, 1e14 = 1 BPS slippage

    /// @notice The poolId inside Convex booster for relevant Curve lpToken.
    uint256 public pid;

    /// @notice The booster address for Convex
    ILido public lido;

    // address public immutable weth;
    IWETH public weth;

    error LpTokenNotSupported();

    function __LidoAdapter_init(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        (uint256 _slippage, uint256 _pid, address _lidoAddress) = abi.decode(
            _protocolConfig.protocolInitData,
            (uint256, uint256, address)
        );

        pid = _pid;
        slippage = _slippage;
        lido = ILido(ILido(_lidoAddress).token());
        weth = IWETH(ILido(_lidoAddress).weth());

        IERC20(address(lido)).approve(
            address(StableSwapSTETH),
            type(uint256).max
        );

        _adapterConfig.underlying.approve(
            address(StableSwapSTETH),
            type(uint256).max
        );
        _adapterConfig.underlying.approve(address(lido), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        uint256 assets = lido.balanceOf(address(this));
        return assets - assets.mulDiv(slippage, 1e18, Math.Rounding.Up);
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
        weth.withdraw(amount); // Grab native Eth from Weth contract
        lido.submit{value: amount}(FEE_RECIPIENT); // Submit to Lido Contract
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
        uint256 amountRecieved = StableSwapSTETH.exchange(
            STETHID,
            WETHID,
            convertToUnderlyingShares(amount),
            0
        );
        weth.deposit{value: amountRecieved}(); // get wrapped eth back
    }

    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    lido.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    receive() external payable {}
}
