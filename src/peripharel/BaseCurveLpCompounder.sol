// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {BaseCurveCompounder} from "./BaseCurveCompounder.sol";

abstract contract BaseCurveLpCompounder is BaseCurveCompounder {
    address internal depositAsset;
    int128 internal indexIn;

    error CompoundFailed();

    function sellRewardsForLpTokenViaCurve(
        address pool,
        address vaultAsset,
        uint256 nCoins,
        bytes memory data
    ) internal {
        sellRewardsViaCurve();

        uint256 amount = IERC20(depositAsset).balanceOf(address(this));

        CurveTradeLibrary.addLiquidity(
            address(pool),
            nCoins,
            indexIn,
            amount,
            0
        );

        amount = IERC20(vaultAsset).balanceOf(address(this));
        uint256 minOut = abi.decode(data, (uint256));
        if (amount < minOut) revert CompoundFailed();
    }

    function setCurveLpCompounderValues(
        address newRouter,
        address[] memory newRewardTokens,
        CurveSwap[] memory newSwaps, // must be ordered like `newRewardTokens`
        int128 indexIn_
    ) internal {
        setCurveTradeValues(newRouter, newRewardTokens, newSwaps);

        // caching
        address asset_ = asset();

        address depositAsset_ = pool.coins(uint256(uint128(indexIn_)));
        if (depositAsset != address(0)) IERC20(depositAsset).approve(asset_, 0);
        IERC20(depositAsset_).approve(asset_, type(uint256).max);

        depositAsset = depositAsset_;
        indexIn = indexIn_;
    }
}
