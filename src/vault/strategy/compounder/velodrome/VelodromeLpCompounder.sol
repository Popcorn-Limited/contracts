// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {VelodromeUtils, IVelodromeRouter, Route} from "./VelodromeUtils.sol";
import {IGauge, ILpToken} from "../../../adapter/velodrome/IVelodrome.sol";

contract VelodromeLpCompounder is StrategyBase {
    // Events
    event Harvest();

    // Errors
    error InvalidConfig();

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION
    //////////////////////////////////////////////////////////////*/

    function verifyAdapterCompatibility(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            Route[][] memory toBaseAssetPaths,
            Route[][] memory toAssetPaths,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, Route[][], Route[][], uint256[], bytes)
            );

        _verifyRewardToken(toBaseAssetPaths, baseAsset);

        _verifyAsset(
            baseAsset,
            IAdapter(msg.sender).asset(),
            toAssetPaths,
            optionalData
        );
    }

    function _verifyRewardToken(
        Route[][] memory toBaseAssetPaths,
        address baseAsset
    ) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            Route[] memory route = toBaseAssetPaths[i];
            if (
                route[0].from != rewardTokens[i] ||
                route[route.length - 1].to != baseAsset
            ) revert InvalidConfig();
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        Route[][] memory toAssetPaths,
        bytes memory
    ) internal virtual {
        // Verify base asset to asset path
        ILpToken lpToken = ILpToken(asset);
        Route[] memory toLp0Route = toAssetPaths[0];
        if (toLp0Route[0].from != baseAsset) revert InvalidConfig();
        if (toLp0Route[toLp0Route.length - 1].to != lpToken.token0())
            revert InvalidConfig();

        if (toAssetPaths.length > 1) {
            Route[] memory toLp1Route = toAssetPaths[1];
            if (toLp1Route[0].from != baseAsset) revert InvalidConfig();
            if (toLp1Route[toLp1Route.length - 1].to != lpToken.token1())
                revert InvalidConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            Route[][] memory toBaseAssetPaths,
            Route[][] memory toAssetPath,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, Route[][], Route[][], uint256[], bytes)
            );

        _approveRewards(router);

        _setUpAsset(
            baseAsset,
            IAdapter(address(this)).asset(),
            router,
            optionalData
        );
    }

    function _approveRewards(address router) internal {
        // Approve all rewardsToken for trading
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20(rewardTokens[i]).approve(router, type(uint256).max);
        }
    }

    function _setUpAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory optionalData
    ) internal virtual {
        if (baseAsset != asset)
            IERC20(baseAsset).approve(router, type(uint256).max);

        ILpToken token = ILpToken(asset);

        IERC20(token.token0()).approve(router, type(uint256).max);
        IERC20(token.token1()).approve(router, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address baseAsset,
            address router,
            Route[][] memory toBaseAssetPaths,
            Route[][] memory toAssetPaths,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, Route[][], Route[][], uint256[], bytes)
            );

        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapToBaseAsset(router, toBaseAssetPaths, minTradeAmounts);

        _getAsset(baseAsset, asset, router, toAssetPaths, optionalData);

        // Deposit new assets into adapter
        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _swapToBaseAsset(
        address router,
        Route[][] memory toBaseAssetPaths,
        uint256[] memory minTradeAmounts
    ) internal {
        // Trade rewards for base asset
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardBal = IERC20(rewardTokens[i]).balanceOf(
                address(this)
            );
            if (rewardBal >= minTradeAmounts[i]) {
                VelodromeUtils.swap(router, toBaseAssetPaths[i], rewardBal);
            }
        }
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address router,
        Route[][] memory toAssetPaths,
        bytes memory optionalData
    ) internal virtual {
        uint256 lp0Amount = IERC20(baseAsset).balanceOf(address(this)) / 2;
        VelodromeUtils.swap(router, toAssetPaths[0], lp0Amount);

        if (toAssetPaths.length > 1) {
            uint256 lp1Amount = IERC20(baseAsset).balanceOf(address(this)) -
                lp0Amount;
            VelodromeUtils.swap(router, toAssetPaths[1], lp0Amount);
        }

        ILpToken LpToken = ILpToken(asset);

        address tokenA = LpToken.token0();
        address tokenB = LpToken.token1();
        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));

        IVelodromeRouter(router).addLiquidity(
            tokenA,
            tokenB,
            false,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }
}
