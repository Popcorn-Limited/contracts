// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {VelodromeTradeLibrary, IRouter, Route} from "./VelodromeTradeLibrary.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

struct SwapStep {
    bytes tradeSwap;
}

abstract contract BaseVelodromeCompounder {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IRouter public velodromeRouter;

    address[] public velodromeSellTokens;
    SwapStep[] internal tradePaths; // for each sellToken there are two trades

    function sellRewardsViaVelodrome() internal {
        // Caching
        IRouter router = velodromeRouter;
        Route memory sellRoute;

        uint256 rewLen = velodromeSellTokens.length;
        for (uint256 i = 0; i < rewLen;) {
            uint256 totAmount = IERC20(velodromeSellTokens[i]).balanceOf(address(this));

            // sell half for tokenA
            uint256 decimals = IERC20Metadata(velodromeSellTokens[i]).decimals();
            uint256 amount = totAmount.mulDiv(10 ** decimals, 2 * (10 ** decimals), Math.Rounding.Floor);

            // sellPath = tradePaths[2 * i];
            Route[] memory routes = new Route[](1);

            if (amount > 0) {
                sellRoute = abi.decode(tradePaths[2 * i].tradeSwap, (Route));
                routes[0] = sellRoute;

                VelodromeTradeLibrary.trade(router, routes, amount);
            }

            // sell the rest for tokenB
            // sellPath = tradePaths[2 * i + 1];
            amount = totAmount - amount;
            if (amount > 0) {
                sellRoute = abi.decode(tradePaths[2 * i + 1].tradeSwap, (Route));
                routes[0] = sellRoute;

                VelodromeTradeLibrary.trade(router, routes, amount);
            }

            unchecked {
                ++i;
            }
        }
    }

    function setVelodromeTradeValues(address newRouter, address[] memory rewTokens, SwapStep[] memory newRoutes) internal {
        // Remove old rewardToken allowance
        uint256 rewardTokenLen = velodromeSellTokens.length;
        if (rewardTokenLen > 0) {
            // caching
            address oldrouter = address(velodromeRouter);
            address[] memory oldRewardTokens = velodromeSellTokens;

            // void approvals
            for (uint256 i = 0; i < rewardTokenLen;) {
                IERC20(oldRewardTokens[i]).forceApprove(oldrouter, 0);

                unchecked {
                    ++i;
                }
            }
        }

        // delete old state
        delete velodromeSellTokens;
        delete tradePaths;

        // Add new allowance + state
        address newRewardToken;
        rewardTokenLen = rewTokens.length;
        for (uint256 i; i < rewardTokenLen;) {
            newRewardToken = address(rewTokens[i]);

            IERC20(newRewardToken).forceApprove(newRouter, type(uint256).max);

            velodromeSellTokens.push(newRewardToken);
            
            // for each rew token there are 2 sell routes
            tradePaths.push(newRoutes[i]);
            tradePaths.push(newRoutes[i + 1]);

            unchecked {
                ++i;
            }
        }

        velodromeRouter = IRouter(newRouter);
    }
}
