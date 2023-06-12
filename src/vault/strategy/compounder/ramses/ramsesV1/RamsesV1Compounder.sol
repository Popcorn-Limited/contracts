// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../../StrategyBase.sol";
import {IRamsesV1Router} from "../../../../../interfaces/external/ramses/ramsesV1/IRamsesRouter.sol";
import {IGauge, ILpToken} from "../../../../adapter/ramses/ramsesV1/IRamsesV1.sol";
import {UniswapV3Utils} from "../../../../../utils/UniswapV3Utils.sol";

contract RamsesV1Compounder is StrategyBase {
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
            address ramsesRouter,
            address uniRouter,
            bytes[] memory toBaseAssetPaths,
            bytes[] memory toAssetPaths,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, address, bytes[], bytes[], uint256[], bytes)
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
        bytes[] memory toBaseAssetPaths,
        address baseAsset
    ) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            address[] memory route = UniswapV3Utils.pathToRoute(
                toBaseAssetPaths[i]
            );
            if (
                route[0] != rewardTokens[i] ||
                route[route.length - 1] != baseAsset
            ) revert InvalidConfig();
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes[] memory toAssetPaths,
        bytes memory
    ) internal virtual {
        // Verify base asset to asset path
        ILpToken lpToken = ILpToken(asset);
        address[] memory toLp0Route = UniswapV3Utils.pathToRoute(
            toAssetPaths[0]
        );
        if (toLp0Route[0] != baseAsset) revert InvalidConfig();
        if (toLp0Route[toLp0Route.length - 1] != lpToken.token0())
            revert InvalidConfig();

        if (toAssetPaths.length > 1) {
            address[] memory toLp1Route = UniswapV3Utils.pathToRoute(
                toAssetPaths[1]
            );
            if (toLp1Route[0] != baseAsset) revert InvalidConfig();
            if (toLp1Route[toLp1Route.length - 1] != lpToken.token1())
                revert InvalidConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address ramsesRouter,
            address uniRouter,
            bytes[] memory toBaseAssetPaths,
            bytes[] memory toAssetPath,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, address, bytes[], bytes[], uint256[], bytes)
            );

        _approveRewards(uniRouter);

        _setUpAsset(
            baseAsset,
            IAdapter(address(this)).asset(),
            ramsesRouter,
            uniRouter,
            optionalData
        );
    }

    function _approveRewards(address uniRouter) internal {
        // Approve all rewardsToken for trading
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20(rewardTokens[i]).approve(uniRouter, type(uint256).max);
        }
    }

    function _setUpAsset(
        address baseAsset,
        address asset,
        address ramsesRouter,
        address uniRouter,
        bytes memory optionalData
    ) internal virtual {
        if (baseAsset != asset) {
            IERC20(baseAsset).approve(uniRouter, type(uint256).max);
        }

        ILpToken token = ILpToken(asset);

        IERC20(token.token0()).approve(ramsesRouter, type(uint256).max);
        IERC20(token.token1()).approve(ramsesRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address baseAsset,
            address ramsesRouter,
            address uniRouter,
            bytes[] memory toBaseAssetPaths,
            bytes[] memory toAssetPaths,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, address, bytes[], bytes[], uint256[], bytes)
            );

        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapToBaseAsset(uniRouter, toBaseAssetPaths, minTradeAmounts);

        _getAsset(
            baseAsset,
            asset,
            ramsesRouter,
            uniRouter,
            toAssetPaths,
            minTradeAmounts,
            optionalData
        );

        // Deposit new assets into adapter
        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _swapToBaseAsset(
        address uniRouter,
        bytes[] memory toBaseAssetPaths,
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

            if (rewardBal >= minTradeAmounts[i])
                UniswapV3Utils.swap(uniRouter, toBaseAssetPaths[i], rewardBal);
        }
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address ramsesRouter,
        address uniRouter,
        bytes[] memory toAssetPaths,
        uint256[] memory minTradeAmounts,
        bytes memory optionalData
    ) internal virtual {
        ILpToken LpToken = ILpToken(asset);

        address token0 = LpToken.token0();
        address token1 = LpToken.token1();
        uint256 lp0Amount = IERC20(baseAsset).balanceOf(address(this)) / 2;
        uint256 lp1Amount;

        if (baseAsset != token0) {
            if (lp0Amount >= minTradeAmounts[0])
                UniswapV3Utils.swap(uniRouter, toAssetPaths[0], lp0Amount);
        }

        if (baseAsset != token1) {
            lp1Amount = IERC20(baseAsset).balanceOf(address(this)) - lp0Amount;
            if (lp1Amount >= minTradeAmounts[1])
                UniswapV3Utils.swap(uniRouter, toAssetPaths[1], lp1Amount);
        }

        uint256 amountA = IERC20(token0).balanceOf(address(this));
        uint256 amountB = IERC20(token1).balanceOf(address(this));

        IRamsesV1Router(ramsesRouter).addLiquidity(
            token0,
            token1,
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
