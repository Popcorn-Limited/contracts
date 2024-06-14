// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IUniswapRouterV2} from "../interfaces/external/uni/IUniswapRouterV2.sol";

library UniswapV2TradeLibrary {
    function trade(
        IUniswapRouterV2 router,
        address[] memory path,
        address receiver,
        uint256 deadline,
        uint256 amount,
        uint256 minOut
    ) internal returns (uint256[] memory amounts) {
        amounts = router.swapExactTokensForTokens(amount, minOut, path, receiver, deadline);
    }

    function addLiquidity(
        IUniswapRouterV2 router,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 amountAMin,
        uint256 amountBMin,
        address receiver,
        uint256 deadline
    ) internal returns (uint256 amountOutA, uint256 amountOutB, uint256 lpAmountOut) {
        (amountOutA, amountOutB, lpAmountOut) =
            router.addLiquidity(tokenA, tokenB, amountA, amountB, amountAMin, amountBMin, receiver, deadline);
    }
}
