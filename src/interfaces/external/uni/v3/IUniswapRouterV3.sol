// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
}

interface IUniswapRouterV3 {
    function exactInput(
        ExactInputParams calldata params
    ) external returns (uint256 amountOut);
}
