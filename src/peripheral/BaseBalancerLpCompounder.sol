// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseBalancerCompounder, BalancerTradeLibrary, TradePath} from "./BaseBalancerCompounder.sol";

struct HarvestValues {
    uint256 amountsInLen;
    address depositAsset;
    uint256 indexIn;
    uint256 indexInUserData;
    bytes32 poolId;
    address[] underlyings;
}

abstract contract BaseBalancerLpCompounder is BaseBalancerCompounder {
    using SafeERC20 for IERC20;

    HarvestValues public harvestValues;

    error CompoundFailed();

    function sellRewardsForLpTokenViaBalancer(address vaultAsset, bytes memory data) internal {
        sellRewardsViaBalancer();

        // caching
        HarvestValues memory harvestValues_ = harvestValues;

        uint256 amount = IERC20(harvestValues_.depositAsset).balanceOf(address(this));

        uint256 amountLPBefore = IERC20(vaultAsset).balanceOf(address(this));

        BalancerTradeLibrary.addLiquidity(
            balancerVault,
            harvestValues_.poolId,
            harvestValues_.underlyings,
            harvestValues_.amountsInLen,
            harvestValues_.indexIn,
            harvestValues_.indexInUserData,
            amount
        );

        amount = IERC20(vaultAsset).balanceOf(address(this)) - amountLPBefore;
        uint256 minOut = abi.decode(data, (uint256));
        if (amount < minOut) revert CompoundFailed();
    }

    function setBalancerLpCompounderValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths,
        HarvestValues memory harvestValues_
    ) internal {
        // Reset old base asset
        if (harvestValues.depositAsset != address(0)) {
            IERC20(harvestValues.depositAsset).forceApprove(address(balancerVault), 0);
        }

        // sets the balancerVault
        setBalancerTradeValues(newBalancerVault, newTradePaths);

        // approve and set new base asset
        IERC20(harvestValues_.depositAsset).forceApprove(newBalancerVault, type(uint256).max);

        harvestValues = harvestValues_;
    }
}
