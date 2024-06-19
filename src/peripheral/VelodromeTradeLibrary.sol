// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {
    IRouter,
    Route,
    ILpToken
} from "../interfaces/external/velodrome/IVelodrome.sol";
import {
    IERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

library VelodromeTradeLibrary {
    function trade(
        IRouter velodromeRouter,
        Route[] memory routes,
        uint256 amount
    ) internal {
        velodromeRouter.swapExactTokensForTokens(
            amount, 
            0, 
            routes, 
            address(this), 
            block.timestamp
        );
    }

    function addLiquidity(
        IRouter velodromeRouter,
        address lpToken
    ) internal {
        (address tokenA, address tokenB) = ILpToken(lpToken).tokens();

        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));

        velodromeRouter.addLiquidity(
            tokenA, 
            tokenB, 
            ILpToken(lpToken).stable(), 
            amountA, 
            amountB, 
            0, 
            0, 
            address(this), 
            block.timestamp
        );
    }
}
