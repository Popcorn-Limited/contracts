// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ICurveRouter, CurveSwap, ICurveLp} from "../strategies/curve/ICurve.sol";
import {CurveTradeLibrary} from "./CurveTradeLibrary.sol";

abstract contract BaseCurveCompounder {
    ICurveRouter public curveRouter;

    address[] public _rewardTokens;
    CurveSwap[] internal swaps; // Must be ordered like `_rewardTokens`

    function sellRewardsViaCurve() internal {
        // caching
        ICurveRouter router = curveRouter;
        CurveSwap[] memory sellSwaps = swaps;

        uint256 amount;
        uint256 rewLen = sellSwaps.length;
        for (uint256 i = 0; i < rewLen;) {
            amount = IERC20(sellSwaps[i].route[0]).balanceOf(address(this));

            if (amount > 0) {
                CurveTradeLibrary.trade(router, sellSwaps[i], amount, 0);
            }

            unchecked {
                ++i;
            }
        }
    }

    function setCurveTradeValues(address newRouter, CurveSwap[] memory newSwaps) internal {
        // Remove old rewardToken allowance
        uint256 rewardTokenLen = _rewardTokens.length;
        if (rewardTokenLen > 0) {
            // caching
            address oldRouter = address(curveRouter);
            address[] memory oldRewardTokens = _rewardTokens;

            // void approvals
            for (uint256 i = 0; i < rewardTokenLen;) {
                IERC20(oldRewardTokens[i]).approve(oldRouter, 0);

                unchecked {
                    ++i;
                }
            }
        }

        // delete old state
        delete _rewardTokens;
        delete swaps;

        // Add new allowance + state
        address newRewardToken;
        rewardTokenLen = newSwaps.length;
        for (uint256 i = 0; i < rewardTokenLen;) {
            newRewardToken = newSwaps[i].route[0];

            IERC20(newRewardToken).approve(newRouter, type(uint256).max);

            _rewardTokens.push(newRewardToken);
            swaps.push(newSwaps[i]);

            unchecked {
                ++i;
            }
        }

        curveRouter = ICurveRouter(newRouter);
    }
}
