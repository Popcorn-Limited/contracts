// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {VelodromeLPCompounder, VelodromeUtils, IERC20, IAdapter} from "./VelodromeLPCompounder.sol";
import {IGauge, ILpToken} from "../../../adapter/velodrome/IVelodrome.sol";

contract VelodromeOptimismCompounder is VelodromeCompounder {
    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes memory toAssetPath,
        bytes memory
    ) internal override {
        address token = address(asset());
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
        address token = address(asset());

        if (baseAsset != token)
            IERC20(baseAsset).approve(router, type(uint256).max);

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
        ILpToken LpToken = ILpToken(asset());

        // Trade base asset for asset
        if (baseAsset != token)
            VelodromeUtils.swap(
                router,
                toAssetPath,
                IERC20(baseAsset).balanceOf(address(this))
            );

        address velodromeRouter = abi.decode(optionalData, (address));

        address tokenA = LpToken.token0();
        address tokenB = LpToken.token1();
        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));

        IGuage(veldromeRouter).addLiquidity(
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
