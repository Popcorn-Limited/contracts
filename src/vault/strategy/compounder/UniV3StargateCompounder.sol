// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {UniV3Compounder, UniswapV3Utils} from "./UniV3Compounder.sol";
import {ISToken, IStargateRouter} from "../../adapter/stargate/IStargate.sol";

contract UniV3StargateCompounder is UniV3Compounder {
    function _verifyAsset(
        address baseAsset,
        bytes memory toAssetPath,
        bytes
    ) internal override {
        address[] memory toAssetRoute = UniswapV3Utils.pathToRoute(toAssetPath);
        if (toAssetRoute[0] != baseAsset) revert InvalidConfig();
        if (
            toAssetRoute[toAssetRoute.length - 1] !=
            ISToken(IAdapter(address(this)).asset()).token()
        ) revert InvalidConfig();
    }

    function _setUpAsset(
        address baseAsset,
        address router,
        bytes memory optionalData
    ) internal override {
        IERC20(baseAsset).approve(router, type(uint256).max);

        address stargateRouter = abi.decode(optionalData, address);
        IERC20(ISToken(IAdapter(address(this)).asset()).token()).approve(
            stargateRouter,
            type(uint256).max
        );
    }

    function _getAsset(
        address baseAsset,
        address router,
        bytes memory toAssetPath,
        bytes memory optionalData
    ) internal override {
        // Trade base asset for asset
        UniswapV3Utils.swap(
            router,
            toAssetPath,
            IERC20(baseAsset).balanceOf(address(this))
        );

        ISToken sToken = ISToken(IAdapter(address(this)).asset());

        address stargateRouter = abi.decode(optionalData, address);
        stargateRouter.addLiquidity(
            sToken.poolId(),
            IERC20(sToken.token()).balanceOf(address(this)),
            address(this)
        );
    }
}
