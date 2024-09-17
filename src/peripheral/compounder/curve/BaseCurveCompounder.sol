// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveRouter, CurveSwap, ICurveLp} from "src/strategies/curve/ICurve.sol";
import {CurveTradeLibrary} from "./CurveTradeLibrary.sol";

abstract contract BaseCurveCompounder {
    using SafeERC20 for IERC20;

    ICurveRouter public curveRouter;

    address[] public _curveSellTokens;
    CurveSwap[] internal curveSwaps; // Must be ordered like `_sellTokens`

    function sellRewardsViaCurve() internal {
        // caching
        ICurveRouter router = curveRouter;
        CurveSwap[] memory sellSwaps = curveSwaps;

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
        uint256 sellTokensLen = _curveSellTokens.length;
        if (sellTokensLen > 0) {
            // caching
            address oldRouter = address(curveRouter);
            address[] memory oldSellTokens = _curveSellTokens;

            // void approvals
            for (uint256 i = 0; i < sellTokensLen;) {
                IERC20(oldSellTokens[i]).forceApprove(oldRouter, 0);

                unchecked {
                    ++i;
                }
            }
        }

        // delete old state
        delete _curveSellTokens;
        delete curveSwaps;

        // Add new allowance + state
        address newRewardToken;
        sellTokensLen = newSwaps.length;
        for (uint256 i = 0; i < sellTokensLen;) {
            newRewardToken = newSwaps[i].route[0];

            IERC20(newRewardToken).forceApprove(newRouter, type(uint256).max);

            _curveSellTokens.push(newRewardToken);
            curveSwaps.push(newSwaps[i]);

            unchecked {
                ++i;
            }
        }

        curveRouter = ICurveRouter(newRouter);
    }
}
