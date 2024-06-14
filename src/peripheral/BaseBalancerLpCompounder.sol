// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
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
    HarvestValues public harvestValues;

    error CompoundFailed();

    function sellRewardsForLpTokenViaBalancer(address vaultAsset, bytes memory data) internal {
        sellRewardsViaBalancer();

        // caching
        HarvestValues memory harvestValues_ = harvestValues;

        uint256 amount = IERC20(harvestValues_.depositAsset).balanceOf(address(this));

        BalancerTradeLibrary.addLiquidity(
            balancerVault,
            harvestValues_.poolId,
            harvestValues_.underlyings,
            harvestValues_.amountsInLen,
            harvestValues_.indexIn,
            harvestValues_.indexInUserData,
            amount
        );

        amount = IERC20(vaultAsset).balanceOf(address(this));
        uint256 minOut = abi.decode(data, (uint256));
        if (amount < minOut) revert CompoundFailed();
    }

    function setBalancerLpCompounderValues(
        address newBalancerVault,
        TradePath[] memory newTradePaths,
        HarvestValues memory harvestValues_
    ) internal {
        setBalancerTradeValues(newBalancerVault, newTradePaths);

        // Reset old base asset
        if (harvestValues.depositAsset != address(0)) {
            IERC20(harvestValues.depositAsset).approve(address(balancerVault), 0);
        }
        // approve and set new base asset
        IERC20(harvestValues_.depositAsset).approve(newBalancerVault, type(uint256).max);

        harvestValues = harvestValues_;
    }
}
