// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {VelodromeUtils, IVelodromeRouter, route} from "./VelodromeUtils.sol";
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
            route[][] memory toBaseAssetPaths,
            route[][] memory toAssetPaths,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, route[][], route[][], uint256[], bytes)
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
        route[][] memory toBaseAssetPaths,
        address baseAsset
    ) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            route[] memory route = toBaseAssetPaths[i];
            if (
                route[0].from != rewardTokens[i] ||
                route[route.length - 1].to != baseAsset
            ) revert InvalidConfig();
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        route[][] memory toAssetPaths,
        bytes memory
    ) internal virtual {
        // Verify base asset to asset path
        ILpToken lpToken = ILpToken(asset);
        route[] memory toLp0Route = toAssetPaths[0];
        if (toLp0Route[0].from != baseAsset) revert InvalidConfig();
        if (toLp0Route[toLp0Route.length - 1].to != lpToken.token0())
            revert InvalidConfig();

        if (toAssetPaths.length > 1) {
            route[] memory toLp1Route = toAssetPaths[1];
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
            route[][] memory toBaseAssetPaths,
            route[][] memory toAssetPath,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, route[][], route[][], uint256[], bytes)
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
        // Approve velo
        IERC20(0x3c8B650257cFb5f272f799F5e2b4e65093a11a05).approve(
            router,
            type(uint256).max
        );

        ILpToken lpToken = ILpToken(asset);

        address token0 = lpToken.token0();
        address token1 = lpToken.token1();

        IERC20(token0).approve(router, type(uint256).max);

        IERC20(token1).approve(router, type(uint256).max);

        if (baseAsset != token0 && baseAsset != token1)
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
            route[][] memory toBaseAssetPaths,
            route[][] memory toAssetPaths,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, route[][], route[][], uint256[], bytes)
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
        route[][] memory toBaseAssetPaths,
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
        route[][] memory toAssetPaths,
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
