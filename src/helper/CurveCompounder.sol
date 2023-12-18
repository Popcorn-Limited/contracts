// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseCompounder, IERC20, HarvestConfig, CompounderConfig} from "../base/BaseCompounder.sol";
import {IBaseAdapter} from "../base/interfaces/IBaseAdapter.sol";
import {ICurveRouter} from "../base/interfaces/external/curve/ICurveRouter.sol";

struct CurveRoute {
    address[9] route;
    uint256[3][4] swapParams;
}

contract CurveCompounder is BaseCompounder {
    address internal router;
    CurveRoute[] internal toBaseAssetRoutes;
    CurveRoute internal toAssetRoute;

    function __CurveCompounder_init(
        HarvestConfig memory _harvestConfig,
        CompounderConfig memory _compounderConfig,
        address _router,
        CurveRoute[] memory _toBaseAssetRoutes,
        CurveRoute memory _toAssetRoute
    ) internal {
        __BaseCompounder_init(_harvestConfig, _compounderConfig);

        for (uint256 i; i < _toBaseAssetRoutes.length; i++) {
            toBaseAssetRoutes.push(_toBaseAssetRoutes[i]);
        }
        toAssetRoute = _toAssetRoute;
        router = _router;
    }

    function _swapToBaseAsset(
        IERC20[] memory rewardTokens,
        bytes memory
    ) internal override {
        CurveRoute[] memory _toBaseAssetRoutes = toBaseAssetRoutes;
        uint256[] memory minTradeAmounts = compounderConfig.minTradeAmounts;

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            uint256 rewardBal = rewardTokens[i].balanceOf(address(this));
            if (rewardBal != 0 && rewardBal >= minTradeAmounts[i])
                ICurveRouter(router).exchange_multiple(
                    _toBaseAssetRoutes[i].route,
                    _toBaseAssetRoutes[i].swapParams,
                    rewardBal,
                    0
                );
        }
    }

    function _getAsset(bytes memory) internal override {
        CurveRoute memory _toAssetRoute = toAssetRoute;

        if (_toAssetRoute.route[0] != address(0)) {
            ICurveRouter(router).exchange_multiple(
                _toAssetRoute.route,
                _toAssetRoute.swapParams,
                compounderConfig.baseAsset.balanceOf(address(this)),
                0
            );
        }
    }
}
