// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseCurveCompounder, CurveTradeLibrary, CurveSwap, ICurveLp} from "./BaseCurveCompounder.sol";

abstract contract BaseCurveLpCompounder is BaseCurveCompounder {
    using SafeERC20 for IERC20;

    address public depositAsset;
    int128 public indexIn;

    error CompoundFailed();

    function sellRewardsForLpTokenViaCurve(address poolAddress, address vaultAsset, uint256 nCoins, bytes memory data)
        internal
    {
        sellRewardsViaCurve();

        uint256 amount = IERC20(depositAsset).balanceOf(address(this));

        uint256 amountLPBefore = IERC20(vaultAsset).balanceOf(address(this));

        CurveTradeLibrary.addLiquidity(poolAddress, nCoins, uint256(uint128(indexIn)), amount, 0);

        amount = IERC20(vaultAsset).balanceOf(address(this)) - amountLPBefore;
        uint256 minOut = abi.decode(data, (uint256));
        if (amount < minOut) revert CompoundFailed();
    }

    function setCurveLpCompounderValues(
        address newRouter,
        CurveSwap[] memory newSwaps,
        address poolAddress,
        int128 indexIn_
    ) internal {
        setCurveTradeValues(newRouter, newSwaps);

        address depositAsset_ = ICurveLp(poolAddress).coins(uint256(uint128(indexIn_)));
        if (depositAsset != address(0)) {
            IERC20(depositAsset).forceApprove(poolAddress, 0);
        }
        IERC20(depositAsset_).forceApprove(poolAddress, type(uint256).max);

        depositAsset = depositAsset_;
        indexIn = indexIn_;
    }
}
