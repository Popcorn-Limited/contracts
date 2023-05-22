// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "src/utils/Path.sol";
import {IVelodromeRouter, route} from "../../../../interfaces/external/velodrome/IVelodromeRouter.sol";
import {ILpToken} from "src/vault/adapter/velodrome/IVelodrome.sol";

library VelodromeUtils {
    using Path for bytes;

    // Swap along an encoded path using known amountIn
    function swap(
        address _router,
        bytes memory _path,
        uint256 _amountIn
    ) internal returns (uint256[] memory amountsOut) {
        address[] memory path = pathToRoute(_path);

        uint256 reserveA1;
        uint256 reserveA2;

        try
            IVelodromeRouter(_router).getReserves(
                path[0],
                path[path.length - 1],
                false
            )
        returns (uint256 reserveA, uint256 reserveB) {
            reserveA1 = reserveA;
        } catch {
            reserveA1 = 0;
        }

        try
            IVelodromeRouter(_router).getReserves(
                path[0],
                path[path.length - 1],
                true
            )
        returns (uint256 reserveA, uint256 reserveB) {
            reserveA2 = reserveA;
        } catch {
            reserveA2 = 0;
        }

        bool stable = reserveA1 >= reserveA2 ? false : true;

        route[] memory routes = new route[](1);
        routes[0] = route(
            0x4200000000000000000000000000000000000042,
            0x4200000000000000000000000000000000000006,
            false
        );

        return
            IVelodromeRouter(_router).swapExactTokensForTokens(
                _amountIn,
                1,
                routes,
                address(this),
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
