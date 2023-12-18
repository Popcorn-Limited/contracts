// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {UniswapV3Utils, IUniV3Pool} from "../../utils/UniswapV3Utils.sol";
import {BaseAdapter, IERC20 as ERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IWETH, ICurveMetapool, IRocketStorage, IrETH, IRocketDepositPool, IRocketDepositSettings, IRocketNetworkBalances} from "./IRocketpool.sol";

contract RocketpoolAdapter is BaseAdapter {
    using SafeERC20 for ERC20;
    using Math for uint256;

    address public constant uniRouter =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    IWETH public constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IRocketStorage public constant rocketStorage =
        IRocketStorage(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);

    bytes32 public constant rocketDepositPoolKey =
        keccak256(abi.encodePacked("contract.address", "rocketDepositPool"));
    bytes32 public constant rETHKey =
        keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"));

    /// @dev the rETH/WETH 0.01% pool is the only one that's used:
    /// https://info.uniswap.org/#/pools/0x553e9c493678d8606d6a5ba284643db2110df823
    uint24 public constant uniSwapFee = 100;

    error NoSharesBurned();
    error InvalidAddress();
    error LpTokenNotSupported();
    error InsufficientSharesReceived();

    function __RocketpoolAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();
        __BaseAdapter_init(_adapterConfig);

        address rocketDepositPoolAddress = rocketStorage.getAddress(
            rocketDepositPoolKey
        );
        address rETHAddress = rocketStorage.getAddress(rETHKey);

        if (rocketDepositPoolAddress == address(0) || rETHAddress == address(0))
            revert InvalidAddress();

        IrETH(rETHAddress).approve(uniRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overridden. If the farm requires the usage of lpToken than this function
     * must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        IrETH rETH = _getRocketToken();
        return rETH.getEthValue(rETH.balanceOf(address(this)));
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
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing
     *      others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        WETH.withdraw(amount);
        _getDepositPool().deposit{value: amount}();
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
     * @dev This function must be overridden. Some farms require the user to into an lpToken before depositing
     * others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        IrETH rETH = _getRocketToken();
        uint256 rETHShares = rETH.getRethValue(amount) + 1;

        if (rETH.getTotalCollateral() > amount) {
            rETH.burn(rETHShares);
            WETH.deposit{value: amount}();
        } else {
            //if there isn't enough ETH in the rocket pool, we swap rETH directly for WETH
            UniswapV3Utils.swap(
                uniRouter,
                address(rETH),
                address(underlying),
                uniSwapFee,
                rETHShares
            );
        }
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    function convertToUnderlyingShares(
        uint256 shares
    ) public view returns (uint256) {
        uint256 supply = _totalUnderlying();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    _getRocketToken().balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    receive() external payable {}

    /// @dev you don't earn any RPL by holding rETH
    function _claim() internal override {}

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/
    function _getDepositPool() internal view returns (IRocketDepositPool) {
        return
            IRocketDepositPool(rocketStorage.getAddress(rocketDepositPoolKey));
    }

    function _getRocketToken() internal view returns (IrETH) {
        return IrETH(rocketStorage.getAddress(rETHKey));
    }
}
