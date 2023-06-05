// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {ICurveRouter} from "../../../../interfaces/external/curve/ICurveRouter.sol";

struct CurveRoute {
    address[9] route;
    uint256[3][4] swapParams;
}

contract CurveCompounder is StrategyBase {
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
            CurveRoute[] memory toBaseAssetRoutes,
            CurveRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, CurveRoute[], CurveRoute, uint256[], bytes)
            );

        _verifyRewardToken(toBaseAssetRoutes, baseAsset);

        _verifyAsset(
            baseAsset,
            IAdapter(msg.sender).asset(),
            toAssetRoute,
            optionalData
        );

        // trading 0 tokens through Curve will cause the tx to revert.
        for (uint i; i < minTradeAmounts.length;) {
            require(minTradeAmounts[i] != 0, "min trade amount has to be > 0");
            unchecked {
                ++i;
            }
        }
    }

    function _verifyRewardToken(
        CurveRoute[] memory toBaseAssetRoutes,
        address baseAsset
    ) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            if (toBaseAssetRoutes[i].route[0] != rewardTokens[i])
                revert InvalidConfig();

            // Loop through the route until there are no more token or the array is over
            uint8 y = 1;
            while (y < 9) {
                if (y == 8 || toBaseAssetRoutes[i].route[y + 1] == address(0))
                    break;
                y++;
            }
            if (toBaseAssetRoutes[i].route[y] != baseAsset)
                revert InvalidConfig();
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        CurveRoute memory toAssetRoute,
        bytes memory
    ) internal virtual {
        // Verify base asset to asset path
        if (baseAsset != asset) {
            if (toAssetRoute.route[0] != baseAsset) revert InvalidConfig();

            // Loop through the route until there are no more token or the array is over
            uint8 i = 1;
            while (i < 9) {
                if (i == 8 || toAssetRoute.route[i + 1] == address(0)) break;
                i++;
            }
            if (toAssetRoute.route[i] != asset) revert InvalidConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            CurveRoute[] memory toBaseAssetRoutes,
            CurveRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (address, address, CurveRoute[], CurveRoute, uint256[], bytes)
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
        bytes memory
    ) internal virtual {
        if (asset != baseAsset)
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
            CurveRoute[] memory toBaseAssetRoutes,
            CurveRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (address, address, CurveRoute[], CurveRoute, uint256[], bytes)
            );
        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();
        _swapToBaseAsset(router, toBaseAssetRoutes, minTradeAmounts);

        // if reward token balance is < minTradeAmounts, we won't trade any reward tokens for the base asset.
        // Because we have no base assets we can't trade to the adapter's underlying asset.
        if (IERC20(baseAsset).balanceOf(address(this)) == 0) {
            emit Harvest();
            return;
        }

        _getAsset(baseAsset, asset, router, toAssetRoute, optionalData);

        // Deposit new assets into adapter
        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _swapToBaseAsset(
        address router,
        CurveRoute[] memory toBaseAssetRoutes,
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
                ICurveRouter(router).exchange_multiple(
                    toBaseAssetRoutes[i].route,
                    toBaseAssetRoutes[i].swapParams,
                    rewardBal,
                    0
                );
        }
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address router,
        CurveRoute memory toAssetRoute,
        bytes memory
    ) internal virtual {
        // Trade base asset for asset
        if (asset != baseAsset)
            ICurveRouter(router).exchange_multiple(
                toAssetRoute.route,
                toAssetRoute.swapParams,
                IERC20(baseAsset).balanceOf(address(this)),
                0
            );
    }
}
