// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ICurveLp, ICurveRouter, CurveSwap} from "../strategies/curve/ICurve.sol";

library CurveTradeLibrary {
    function trade(ICurveRouter router, CurveSwap memory swap, uint256 amount, uint256 minOut) internal {
        router.exchange(swap.route, swap.swapParams, amount, minOut, swap.pools);
    }

    function addLiquidity(address pool, uint256 nCoins, uint256 indexIn, uint256 amount, uint256 minOut) internal {
        uint256[] memory amounts = new uint256[](nCoins);
        amounts[indexIn] = amount;

        ICurveLp(pool).add_liquidity(amounts, minOut);
    }
}
