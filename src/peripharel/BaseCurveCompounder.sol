// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ICurveLp, IGauge, ICurveRouter, CurveSwap, IMinter} from "../strategies/curve/ICurve.sol";
import {CurveTradeLibrary} from "./CurveTradeLibrary.sol";

abstract contract BaseCurveCompounder {
    ICurveRouter public curveRouter;

    address[] internal _rewardTokens;
    CurveSwap[] internal swaps; // Must be ordered like `_rewardTokens`

    function _sellRewards() internal {
        // caching
        ICurveRouter router = curveRouter;
        address[] memory sellTokens = _rewardTokens;
        CurveSwap[] memory sellSwaps = swaps;

        uint256 amount;
        uint256 rewLen = sellTokens.length;
        for (uint256 i = 0; i < rewLen; i++) {
            amount = IERC20(sellTokens[i]).balanceOf(address(this));

            if (amount > 0) {
                CurveTradeLibrary.trade(router, sellSwaps[i], amount, 0);
            }
        }
    }

    function _setTradeValues(
        address newRouter,
        address[] memory newRewardTokens,
        CurveSwap[] memory newSwaps // must be ordered like `newRewardTokens`
    ) internal {
        uint256 rewardTokenLen = _rewardTokens.length;
        if (rewardTokenLen > 0) {
            // caching
            address oldRouter = address(curveRouter);
            address memory oldRewardTokens = _rewardTokens;

            // void approvals
            for (uint256 i = 0; i < rewardTokenLen; i++) {
                IERC20(oldRewardTokens[i]).approve(oldRouter, 0);
            }
        }

        delete swaps;
        rewardTokenLen = newRewardTokens.length;
        for (uint256 i = 0; i < rewardTokenLen; i++) {
            IERC20(newRewardTokens[i]).approve(newRouter, type(uint256).max);
            swaps.push(newSwaps[i]);
        }

        _rewardTokens = newRewardTokens;
        curveRouter = ICurveRouter(newRouter);
    }

    function _approveSwapTokens(
        address[] memory oldRewardTokens,
        address[] memory newRewardTokens,
        address oldRouter,
        address newRouter
    ) internal {}
}
