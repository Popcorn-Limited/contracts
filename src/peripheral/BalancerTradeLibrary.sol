// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {
    IBalancerVault,
    SwapKind,
    IAsset,
    BatchSwapStep,
    FundManagement,
    JoinPoolRequest
} from "../interfaces/external/balancer/IBalancerVault.sol";

library BalancerTradeLibrary {
    function trade(
        IBalancerVault balancerVault,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        int256[] memory limits,
        uint256 amount
    ) internal {
        // Use the actual rewardBal as the amount to sell
        swaps[0].amount = amount;

        // Swap
        balancerVault.batchSwap(
            SwapKind.GIVEN_IN,
            swaps,
            assets,
            FundManagement(address(this), false, payable(address(this)), false),
            limits,
            block.timestamp
        );
    }

    function addLiquidity(
        IBalancerVault balancerVault,
        bytes32 poolId,
        address[] memory underlyings,
        uint256 amountsInLen,
        uint256 indexIn,
        uint256 indexInUserData,
        uint256 amount
    ) internal {
        uint256[] memory amounts = new uint256[](underlyings.length);
        // Use the actual base asset balance to pool.
        amounts[indexIn] = amount;

        // Some pools need to be encoded with a different length array than the actual input amount array
        bytes memory userData;
        if (underlyings.length != amountsInLen) {
            uint256[] memory amountsIn = new uint256[](amountsInLen);
            amountsIn[indexInUserData] = amount;
            userData = abi.encode(1, amountsIn, 0); // Exact In Enum, inAmounts, minOut
        } else {
            userData = abi.encode(1, amounts, 0); // Exact In Enum, inAmounts, minOut
        }

        // Pool base asset
        balancerVault.joinPool(
            poolId, address(this), address(this), JoinPoolRequest(underlyings, amounts, userData, false)
        );
    }
}
