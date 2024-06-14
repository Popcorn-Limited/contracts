// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseUniV2Compounder, UniswapV2TradeLibrary, SwapStep} from "./BaseUniV2Compounder.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseUniV2LpCompounder is BaseUniV2Compounder {
    using SafeERC20 for IERC20;

    address[2] public depositAssets;
    int128 public indexIn;

    error CompoundFailed();

    function sellRewardsForLpTokenViaUniswap(address vaultAsset, address to, uint256 deadline, bytes memory data)
        internal
    {
        sellRewardsForBaseTokensViaUniswapV2();

        address tokenA = depositAssets[0];
        address tokenB = depositAssets[1];

        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));

        if (amountA > 0 && amountB > 0) {
            UniswapV2TradeLibrary.addLiquidity(
                uniswapRouter, depositAssets[0], depositAssets[1], amountA, amountB, 0, 0, to, deadline
            );

            uint256 amountLP = IERC20(vaultAsset).balanceOf(address(this));
            uint256 minOut = abi.decode(data, (uint256));
            if (amountLP < minOut) revert CompoundFailed();
        }
    }

    function setUniswapLpCompounderValues(
        address newRouter,
        address[2] memory newDepositAssets,
        address[] memory rewardTokens,
        SwapStep[] memory newSwaps
    ) internal {
        setUniswapTradeValues(newRouter, rewardTokens, newSwaps);

        address tokenA = newDepositAssets[0];
        address tokenB = newDepositAssets[1];

        address oldTokenA = depositAssets[0];
        address oldTokenB = depositAssets[1];

        if (oldTokenA != address(0)) {
            IERC20(oldTokenA).forceApprove(address(uniswapRouter), 0);
        }
        if (oldTokenB != address(0)) {
            IERC20(oldTokenB).forceApprove(address(uniswapRouter), 0);
        }

        IERC20(tokenA).forceApprove(address(uniswapRouter), type(uint256).max);
        IERC20(tokenB).forceApprove(address(uniswapRouter), type(uint256).max);

        depositAssets = newDepositAssets;
    }
}
