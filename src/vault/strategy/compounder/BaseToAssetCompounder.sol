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

contract BaseToAssetCompounder is StrategyBase {
    // Events
    event Harvest();

    // Errors
    error InvalidRoute();
    error InvalidConfig();

    function verifyAdapterCompatibility(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            address[][] memory toBaseAssetRoutes,
            address[] memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, address[][], address[], uint256[], bytes)
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
            address router,
            address[][] memory toBaseAssetRoutes,
            address[] memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, address[][], address[], uint256[], bytes)
            );

        // Approve all rewardsToken for trading
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20(rewardTokens[i]).approve(router, type(uint256).max);
        }
        IERC20(baseAsset).approve(router, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address baseAsset,
            address router,
            address[][] memory toBaseAssetRoutes,
            address[] memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, address[][], address[], uint256[], bytes)
            );

        address asset = IAdapter(address(this)).asset();
        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        uint256 len = toBaseAssetRoutes.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardBal = IERC20(toBaseAssetRoutes[i][0]).balanceOf(
                address(this)
            );
            if (rewardBal >= minTradeAmounts[i])
                _trade(router, toBaseAssetRoutes[i], rewardBal, optionalData);
        }

        _trade(
            router,
            toAssetRoute,
            IERC20(baseAsset).balanceOf(address(this)),
            optionalData
        );

        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _trade(
        address router,
        address[] memory route,
        uint256 amount,
        bytes memory optionalData
    ) internal virtual {}
}
