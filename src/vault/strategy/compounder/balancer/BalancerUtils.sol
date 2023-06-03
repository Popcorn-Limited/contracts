// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "src/utils/Path.sol";
import {IBalancerVault, SwapKind, BatchSwapStep, IAsset, FundManagement} from "../../../../interfaces/external/balancer/IBalancerVault.sol";
import {IGauge} from "src/vault/adapter/balancer/IBalancer.sol";

library BalancerUtils {
    using Path for bytes;

    function swap(
        address _router,
        bytes32[] memory _poolIds,
        uint256[] memory _assetInIndexes,
        uint256[] memory _assetOutIndexes,
        uint256[] memory _amountsIn,
        address[] memory _assets
    ) internal returns (uint256[] memory amountsOut) {
        uint256 len = _poolIds.length;

        BatchSwapStep[] swaps = new BatchSwapStep[](len);
        int256[] limits = new int256[](len);

        for (uint256 i; i < len; ++i) {
            swaps[i] = BatchSwapStep(
                _poolIds[i],
                _assetInIndexes[i],
                _assetOutIndexes[i],
                _amountsIn[i],
                ""
            );
        }

        FundManagement funds = FundManagement(
            address(this),
            false,
            payable(address(this)),
            false
        );

        return
            IBalancerVault(_router).batchSwap(
                SwapKind.GIVEN_IN,
                swaps,
                _assets,
                funds,
                limits,
                block.timestamp
            );
    }

    // Swap along a token route using known fees and amountIn
    function swap(
        address _router,
        address[] memory _route,
        uint24[] memory _fee,
        uint256 _amountIn
    ) internal returns (uint256[] memory amountsOut) {
        return swap(_router, routeToPath(_route, _fee), _amountIn);
    }

    // Convert encoded path to token route
    function pathToRoute(
        bytes memory _path
    ) internal pure returns (address[] memory) {
        uint256 numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint256 i; i < numPools; i++) {
            (address tokenA, address tokenB, ) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    // Convert token route to encoded path
    // uint24 type for fees so path is packed tightly
    function routeToPath(
        address[] memory _route,
        uint24[] memory _fee
    ) internal pure returns (bytes memory path) {
        path = abi.encodePacked(_route[0]);
        uint256 feeLength = _fee.length;
        for (uint256 i = 0; i < feeLength; i++) {
            path = abi.encodePacked(path, _fee[i], _route[i + 1]);
        }
    }
}
