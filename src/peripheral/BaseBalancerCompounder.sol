// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {BalancerTradeLibrary, IBalancerVault, IAsset, BatchSwapStep} from "./BalancerTradeLibrary.sol";

struct TradePath {
    IAsset[] assets;
    int256[] limits;
    bytes swaps;
}

abstract contract BaseBalancerCompounder {
    IBalancerVault public balancerVault;

    TradePath[] public tradePaths;
    address[] public _rewardTokens;

    function sellRewardsViaBalancer() internal {
        // Caching
        IBalancerVault router = balancerVault;
        TradePath[] memory sellPaths = tradePaths;

        uint256 amount;
        uint256 rewLen = sellPaths.length;
        for (uint256 i = 0; i < rewLen;) {
            amount = IERC20(address(sellPaths[i].assets[0])).balanceOf(address(this));

            if (amount > 0) {
                // Decode since nested struct[] isnt allowed in storage
                BatchSwapStep[] memory swaps = abi.decode(sellPaths[i].swaps, (BatchSwapStep[]));

                BalancerTradeLibrary.trade(router, swaps, sellPaths[i].assets, sellPaths[i].limits, amount);
            }

            unchecked {
                ++i;
            }
        }
    }

    function setBalancerTradeValues(address newBalancerVault, TradePath[] memory newTradePaths) internal {
        // Remove old rewardToken allowance
        uint256 rewardTokenLen = _rewardTokens.length;
        if (rewardTokenLen > 0) {
            // caching
            address oldBalancerVault = address(balancerVault);
            address[] memory oldRewardTokens = _rewardTokens;

            // void approvals
            for (uint256 i = 0; i < rewardTokenLen;) {
                IERC20(oldRewardTokens[i]).approve(oldBalancerVault, 0);

                unchecked {
                    ++i;
                }
            }
        }

        // delete old state
        delete _rewardTokens;
        delete tradePaths;

        // Add new allowance + state
        address newRewardToken;
        rewardTokenLen = newTradePaths.length;
        for (uint256 i; i < rewardTokenLen;) {
            newRewardToken = address(newTradePaths[i].assets[0]);

            IERC20(newRewardToken).approve(newBalancerVault, type(uint256).max);

            _rewardTokens.push(newRewardToken);
            tradePaths.push(newTradePaths[i]);

            unchecked {
                ++i;
            }
        }

        balancerVault = IBalancerVault(newBalancerVault);
    }
}
