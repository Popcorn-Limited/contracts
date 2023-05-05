// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Path.sol";
import {IUniswapRouterV3, ExactInputSingleParams, ExactInputParams} from "../interfaces/external/uni/v3/IUniswapRouterV3.sol";

library UniswapV3Utils {
    using Path for bytes;

    // Swap along an encoded path using known amountIn
    function swap(
        address _router,
        bytes memory _path,
        uint256 _amountIn
    ) internal returns (uint256 amountOut) {
        return
            IUniswapRouterV3(_router).exactInput(
                ExactInputParams({
                    path: _path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amountIn,
                    amountOutMinimum: 0
                })
            );
    }

    // Swap along a token route using known fees and amountIn
    function swap(
        address _router,
        address[] memory _route,
        uint24[] memory _fee,
        uint256 _amountIn
    ) internal returns (uint256 amountOut) {
        return swap(_router, routeToPath(_route, _fee), _amountIn);
    }

    function swapSingle(address _router, uint256 amountIn) internal {
        IUniswapRouterV3(_router).exactInputSingle(
            ExactInputSingleParams({
                tokenIn: 0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6,
                tokenOut: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
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
