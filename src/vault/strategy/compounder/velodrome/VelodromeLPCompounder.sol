// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {VelodromeCompounder, VelodromeUtils, IVelodromeRouter, IERC20, IAdapter, IGauge, ILpToken} from "./VelodromeCompounder.sol";

contract VelodromeLpCompounder is VelodromeCompounder {
    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes memory toAssetPath,
        bytes memory optionalData
    ) internal override {
        address velodromeRouter = abi.decode(optionalData, (address));

        if (IVelodromeRouter(velodromeRouter).isPair(asset) == false) {
            revert InvalidConfig();
        }

        address token = asset;

        if (baseAsset != token) {
            address[] memory toAssetRoute = VelodromeUtils.pathToRoute(
                toAssetPath
            );
            if (toAssetRoute[0] != baseAsset) revert InvalidConfig();
            if (toAssetRoute[toAssetRoute.length - 1] != token)
                revert InvalidConfig();
        }
    }

    function _setUpAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory optionalData
    ) internal override {
        address token = asset;

        if (baseAsset != token)
            IERC20(baseAsset).approve(router, type(uint256).max);

        IERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05).approve(
            router,
            type(uint256).max
        );

        IERC20(ILpToken(token).token0()).approve(router, type(uint256).max);

        IERC20(ILpToken(token).token1()).approve(router, type(uint256).max);

        address velodromeRouter = abi.decode(optionalData, (address));
        IERC20(token).approve(velodromeRouter, type(uint256).max);
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory toAssetPath,
        bytes memory optionalData
    ) internal override {
        ILpToken LpToken = ILpToken(asset);

        address token = asset;

        address velodromeRouter = abi.decode(optionalData, (address));

        address tokenA = LpToken.token0();
        address tokenB = LpToken.token1();
        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));

        IVelodromeRouter(velodromeRouter).addLiquidity(
            tokenA,
            tokenB,
            false,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
