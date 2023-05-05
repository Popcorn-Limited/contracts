// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {UniV3Compounder, UniswapV3Utils, IERC20, IAdapter} from "./UniV3Compounder.sol";
import {ISToken, IStargateRouter} from "../../adapter/stargate/IStargate.sol";

contract UniV3StargateCompounder is UniV3Compounder {
    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes memory toAssetPath,
        bytes memory
    ) internal override {
        address token = ISToken(asset).token();
        if (baseAsset != token) {
            address[] memory toAssetRoute = UniswapV3Utils.pathToRoute(
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
        address token = ISToken(asset).token();

        if (baseAsset != token)
            IERC20(baseAsset).approve(router, type(uint256).max);

        address stargateRouter = abi.decode(optionalData, (address));
        IERC20(token).approve(stargateRouter, type(uint256).max);
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory toAssetPath,
        bytes memory optionalData
    ) internal override {
        ISToken sToken = ISToken(asset);
        address token = sToken.token();

        // Trade base asset for asset
        if (baseAsset != token)
            UniswapV3Utils.swap(
                router,
                toAssetPath,
                IERC20(baseAsset).balanceOf(address(this))
            );

        address stargateRouter = abi.decode(optionalData, (address));
        IStargateRouter(stargateRouter).addLiquidity(
            sToken.poolId(),
            IERC20(token).balanceOf(address(this)),
            address(this)
        );
    }
}
