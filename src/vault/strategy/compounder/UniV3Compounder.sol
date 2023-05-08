// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../StrategyBase.sol";
import {UniswapV3Utils} from "../../../utils/UniswapV3Utils.sol";

contract UniV3Compounder is StrategyBase {
    // Events
    event Harvest();

    // Errors
    error InvalidConfig();

    function verifyAdapterCompatibility(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            bytes[] memory toBaseAssetPaths,
            bytes memory toAssetPath,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, bytes[], bytes, uint256[], bytes)
            );

        _verifyRewardToken(toBaseAssetPaths, baseAsset);

        _verifyAsset(
            baseAsset,
            IAdapter(msg.sender).asset(),
            toAssetPath,
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

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            bytes[] memory toBaseAssetPaths,
            bytes memory toAssetPath,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, bytes[], bytes, uint256[], bytes)
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

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address baseAsset,
            address router,
            bytes[] memory toBaseAssetPaths,
            bytes memory toAssetPath,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, bytes[], bytes, uint256[], bytes)
            );

        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapToBaseAsset(router, toBaseAssetPaths, minTradeAmounts);

        _getAsset(baseAsset, asset, router, toAssetPath, optionalData);

        // Deposit new assets into adapter
        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _swapToBaseAsset(
        address router,
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
                UniswapV3Utils.swap(router, toBaseAssetPaths[i], rewardBal);
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes memory toAssetPath,
        bytes memory
    ) internal virtual {
        if (baseAsset != asset) {
            // Verify base asset to asset path
            address[] memory toAssetRoute = UniswapV3Utils.pathToRoute(
                toAssetPath
            );
            if (toAssetRoute[0] != baseAsset) revert InvalidConfig();
            if (toAssetRoute[toAssetRoute.length - 1] != asset)
                revert InvalidConfig();
        }
    }

    function _setUpAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory
    ) internal virtual {
        if (asset != baseAsset)
            IERC20(baseAsset).approve(router, type(uint256).max);
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address router,
        bytes memory toAssetPath,
        bytes memory
    ) internal virtual {
        // Trade base asset for asset
        if (asset != baseAsset)
            UniswapV3Utils.swap(
                router,
                toAssetPath,
                IERC20(baseAsset).balanceOf(address(this))
            );
    }
}
