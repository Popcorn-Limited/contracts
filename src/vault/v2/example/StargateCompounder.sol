// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {StargateAdapter, IERC20} from "./StargateAdapter.sol";
import {CurveCompounder, CurveRoute} from "./CurveCompounder.sol";

contract StargateCompounder is StargateAdapter, CurveCompounder {
    // TODO pack these variables better
    function __StargateCompounder_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        bool _useLpToken,
        IERC20[] memory _rewardTokens,
        address _registry,
        bytes memory _stargateInitData,
        bool _autoHarvest,
        bytes memory _harvestData,
        IERC20 _baseAsset,
        uint256[] memory _minTradeAmounts,
        bool _depositLpToken,
        CurveRoute[] memory _toBaseAssetRoutes,
        CurveRoute memory _toAssetRoute,
        address _router
    ) internal onlyInitializing {
        __StargateAdapter_init(
            _underlying,
            _lpToken,
            _useLpToken,
            _rewardTokens,
            _registry,
            _stargateInitData
        );
        __CurveCompounder_init(
            _autoHarvest,
            _harvestData,
            _baseAsset,
            _minTradeAmounts,
            _depositLpToken,
            _toBaseAssetRoutes,
            _toAssetRoute,
            _router
        );
    }
}
