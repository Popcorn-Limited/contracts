// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {UniswapV2TradeLibrary, IUniswapRouterV2} from "./UniswapV2TradeLibrary.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

struct SwapStep {
    address[] path;
}

abstract contract BaseUniV2Compounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IUniswapRouterV2 public uniswapRouter;

    address[] public sellTokens;
    SwapStep[] internal sellSwaps; // for each sellToken there are two paths.

    // sell half the rewards for a pool tokenA and half for the tokenB
    function sellRewardsForBaseTokensViaUniswapV2() internal {
        // caching
        IUniswapRouterV2 router = uniswapRouter;
        SwapStep memory swap;

        uint256 rewLen = sellTokens.length;
        for (uint256 i = 0; i < rewLen;) {
            uint256 totAmount = IERC20(sellTokens[i]).balanceOf(address(this));

            // sell half for tokenA
            uint256 decimals = IERC20Metadata(sellTokens[i]).decimals();
            uint256 amount = totAmount.mulDiv(10 ** decimals, 2 * (10 ** decimals), Math.Rounding.Floor);

            swap = sellSwaps[2 * i];

            if (amount > 0) {
                UniswapV2TradeLibrary.trade(router, swap.path, address(this), block.timestamp, amount, 0);
            }

            // sell the rest for tokenB
            swap = sellSwaps[2 * i + 1];
            amount = totAmount - amount;
            if (amount > 0) {
                UniswapV2TradeLibrary.trade(router, swap.path, address(this), block.timestamp, amount, 0);
            }

            unchecked {
                ++i;
            }
        }
    }

    // sell all rewards for a single token
    function sellRewardsViaUniswapV2() internal {
        IUniswapRouterV2 router = uniswapRouter;
        SwapStep memory swap;

        uint256 rewLen = sellTokens.length;
        for (uint256 i = 0; i < rewLen;) {
            uint256 totAmount = IERC20(sellTokens[i]).balanceOf(address(this));
            swap = sellSwaps[i];

            if (totAmount > 0) {
                UniswapV2TradeLibrary.trade(router, swap.path, address(this), block.timestamp, totAmount, 0);
            }

            unchecked {
                ++i;
            }
        }
    }

    function setUniswapTradeValues(address newRouter, address[] memory rewTokens, SwapStep[] memory newSwaps)
        internal
    {
        // Remove old rewardToken allowance
        uint256 sellTokensLen = sellTokens.length;
        if (sellTokensLen > 0) {
            // caching
            address oldRouter = address(uniswapRouter);
            address[] memory oldSellTokens = sellTokens;

            // void approvals
            for (uint256 i = 0; i < sellTokensLen;) {
                IERC20(oldSellTokens[i]).forceApprove(oldRouter, 0);

                unchecked {
                    ++i;
                }
            }
        }

        // delete old state
        delete sellTokens;
        delete sellSwaps;

        // Add new allowance + state
        address newRewardToken;
        sellTokensLen = rewTokens.length;
        for (uint256 i = 0; i < sellTokensLen;) {
            newRewardToken = rewTokens[i];

            IERC20(newRewardToken).forceApprove(newRouter, type(uint256).max);

            sellTokens.push(newRewardToken);

            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < newSwaps.length;) {
            sellSwaps.push(newSwaps[i]);
            unchecked {
                ++i;
            }
        }

        uniswapRouter = IUniswapRouterV2(newRouter);
    }
}
