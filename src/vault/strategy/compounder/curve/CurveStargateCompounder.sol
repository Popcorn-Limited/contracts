// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {CurveCompounder, IAdapter, IWithRewards, ICurveRouter, CurveRoute} from "./CurveCompounder.sol";
import {ISToken, IStargateRouter} from "../../../adapter/stargate/IStargate.sol";

contract CurveStargateCompounder is CurveCompounder {
    function _verifyAsset(
        address baseAsset,
        address asset,
        CurveRoute memory toAssetRoute,
        bytes memory
    ) internal override {
        address token = ISToken(asset).token();

        // Verify base asset to asset path
        if (baseAsset != token) {
            if (toAssetRoute.route[0] != baseAsset) revert InvalidConfig();

            // Loop through the route until there are no more token or the array is over
            uint8 i = 1;
            while (i < 9) {
                if (i == 8 || toAssetRoute.route[i + 1] == address(0)) break;
                i++;
            }
            if (toAssetRoute.route[i] != token) revert InvalidConfig();
        }
    }

    function _setUpAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory optionalData
    ) internal override {
        address token = ISToken(asset).token();

        if (asset != token)
            IERC20(baseAsset).approve(router, type(uint256).max);

        address stargateRouter = abi.decode(optionalData, (address));
        IERC20(token).approve(stargateRouter, type(uint256).max);
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address router,
        CurveRoute memory toAssetRoute,
        bytes memory optionalData
    ) internal override {
        ISToken sToken = ISToken(asset);
        address token = sToken.token();

        // Trade base asset for asset
        if (baseAsset != token)
            ICurveRouter(router).exchange_multiple(
                toAssetRoute.route,
                toAssetRoute.swapParams,
                IERC20(baseAsset).balanceOf(address(this)),
                0
            );

        address stargateRouter = abi.decode(optionalData, (address));
        IStargateRouter(stargateRouter).addLiquidity(
            sToken.poolId(),
            IERC20(token).balanceOf(address(this)),
            address(this)
        );
    }
}
