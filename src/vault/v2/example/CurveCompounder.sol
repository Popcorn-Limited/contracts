// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseCompounder, IERC20} from "../base/BaseCompounder.sol";
import {IBaseAdapter} from "../base/interfaces/IBaseAdapter.sol";
import {ICurveRouter} from "../../../interfaces/external/curve/ICurveRouter.sol";

struct CurveRoute {
    address[9] route;
    uint256[3][4] swapParams;
}

contract CurveCompounder is BaseCompounder {
    address internal router;
    CurveRoute[] internal toBaseAssetRoutes;
    CurveRoute internal toAssetRoute;

    function __CurveCompounder_init(
        bool _autoHarvest,
        bytes memory _harvestData,
        IERC20 _baseAsset,
        uint256[] memory _minTradeAmounts,
        bool _depositLpToken,
        CurveRoute[] memory _toBaseAssetRoutes,
        CurveRoute memory _toAssetRoute,
        address _router
    ) internal {
        __BaseCompounder_init(
            _autoHarvest,
            _harvestData,
            _baseAsset,
            _minTradeAmounts,
            _depositLpToken
        );

        toBaseAssetRoutes = _toBaseAssetRoutes;
        toAssetRoute = _toAssetRoute;
    }

    function _swapToBaseAsset(bytes memory optionalData) internal override {
        address[] memory rewardTokens = IBaseAdapter(address(this))
            .rewardTokens();
        CurveRoute[] memory _toBaseAssetRoutes = toBaseAssetRoutes;

        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardBal = IERC20(rewardTokens[i]).balanceOf(
                address(this)
            );
            if (rewardBal >= minTradeAmounts[i])
                ICurveRouter(router).exchange_multiple(
                    _toBaseAssetRoutes[i].route,
                    _toBaseAssetRoutes[i].swapParams,
                    rewardBal,
                    0
                );
        }
    }

    function _getAsset(bytes memory optionalData) internal override {
        CurveRoute memory _toAssetRoute = toAssetRoute;

        if (_toAssetRoute.route[0] != address(0)) {
            ICurveRouter(router).exchange_multiple(
                _toAssetRoute.route,
                _toAssetRoute.swapParams,
                IERC20(baseAsset).balanceOf(address(this)),
                0
            );
        }
    }
}
