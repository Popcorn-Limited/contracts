// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IWithRewards} from "../../../interfaces/vault/IWithRewards.sol";
import {IEIP165} from "../../../interfaces/IEIP165.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IUniswapRouterV2} from "../../../interfaces/external/uni/IUniswapRouterV2.sol";
import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../StrategyBase.sol";

interface IRouter {
    function trade(
        address[] memory route,
        uint256 amount,
        uint256 minAmount
    ) external returns (uint256);
}

contract BaseToAssetCompounder is StrategyBase {
    // Events
    event Harvest();

    // Errors
    error InvalidRoute();
    error InvalidConfig();

    function verifyAdapterCompatibility(bytes memory data) public override {
        (
            address baseAsset,
            address toBaseAssetRouter,
            address toAssetRouter,
            address[4][5] memory toBaseAssetRoutes,
            address[4] memory toAssetRoute,
            uint8[5] memory toBaseAssetLen,
            uint8 toAssetLen,
            uint256[5] memory minTradeAmounts
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (
                    address,
                    address,
                    address,
                    address[4][5],
                    address[4],
                    uint8[5],
                    uint8,
                    uint256[5]
                )
            );

        address asset = IAdapter(address(this)).asset();

        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (toBaseAssetRoutes[i][0] != rewardTokens[i])
                revert InvalidConfig();
            if (toBaseAssetRoutes[i][toBaseAssetLen[i] - 1] != baseAsset)
                revert InvalidConfig();
        }

        if (toAssetRoute[0] != baseAsset) revert InvalidConfig();
        if (toAssetRoute[toAssetLen - 1] != asset) revert InvalidConfig();
    }

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address toBaseAssetRouter,
            address toAssetRouter,
            address[4][5] memory toBaseAssetRoutes,
            address[4] memory toAssetRoute,
            uint8[5] memory toBaseAssetLen,
            uint8 toAssetLen,
            uint256[5] memory minTradeAmounts
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (
                    address,
                    address,
                    address,
                    address[4][5],
                    address[4],
                    uint8[5],
                    uint8,
                    uint256[5]
                )
            );

        // Approve all rewardsToken for trading
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20(rewardTokens[i]).approve(
                toBaseAssetRouter,
                type(uint256).max
            );
        }
        IERC20(baseAsset).approve(toAssetRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address baseAsset,
            address toBaseAssetRouter,
            address toAssetRouter,
            address[4][5] memory toBaseAssetRoutes,
            address[4] memory toAssetRoute,
            uint8[5] memory toBaseAssetLen,
            uint8 toAssetLen,
            uint256[5] memory minTradeAmounts
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (
                    address,
                    address,
                    address,
                    address[4][5],
                    address[4],
                    uint8[5],
                    uint8,
                    uint256[5]
                )
            );
        address asset = IAdapter(address(this)).asset();
        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapRewardsToBase(
            toBaseAssetRouter,
            toBaseAssetRoutes,
            toBaseAssetLen,
            minTradeAmounts
        );

        _swapBaseToAsset(toAssetRouter, baseAsset, toAssetRoute, toAssetLen);

        uint256 balAfter = IERC20(asset).balanceOf(address(this));

        IAdapter(address(this)).strategyDeposit(balAfter - balBefore, 0);

        emit Harvest();
    }

    // Swap all rewards to base asset.
    function _swapRewardsToBase(
        address toBaseAssetRouter,
        address[4][5] memory toBaseAssetRoutes,
        uint8[5] memory toBaseAssetLen,
        uint256[5] memory minTradeAmounts
    ) internal virtual {
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardAmount = IERC20(rewardTokens[i]).balanceOf(
                address(this)
            );

            if (rewardAmount > minTradeAmounts[i]) {
                // clean up trade route
                address[] memory route = new address[](toBaseAssetLen[i]);
                for (uint256 idx; idx < toBaseAssetLen[i]; idx++) {
                    route[idx] = toBaseAssetRoutes[i][idx];
                }

                // route, amount, minOut
                IRouter(toBaseAssetRouter).trade(route, rewardAmount, 0);
            }
        }
    }

    function _swapBaseToAsset(
        address toAssetRouter,
        address baseAsset,
        address[4] memory toAssetRoute,
        uint8 toAssetLen
    ) internal virtual {
        uint256 amount = IERC20(baseAsset).balanceOf(address(this));

        if (amount > 0) {
            // clean up trade route
            address[] memory route = new address[](toAssetLen);
            for (uint256 i; i < toAssetLen; i++) {
                route[i] = toAssetRoute[i];
            }

            // route, amount, minOut
            IRouter(toAssetRouter).trade(route, amount, 0);
        }
    }
} 