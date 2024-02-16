// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest} from "../../../../interfaces/external/balancer/IBalancerVault.sol";

struct BalancerRoute {
    BatchSwapStep[] swaps;
    IAsset[] assets;
    int256[] limits;
}

contract BalancerCompounder is StrategyBase {
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
            address vault,
            BalancerRoute[] memory toBaseAssetRoutes,
            BalancerRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    BalancerRoute[],
                    BalancerRoute,
                    uint256[],
                    bytes
                )
            );

        _verifyRewardToken(toBaseAssetRoutes, baseAsset);

        _verifyAsset(
            baseAsset,
            IAdapter(msg.sender).asset(),
            vault,
            toAssetRoute,
            optionalData
        );
    }

    function _verifyRewardToken(
        BalancerRoute[] memory toBaseAssetRoutes,
        address baseAsset
    ) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            // Verify that the first token in is the rewardToken
            if (
                address(
                    toBaseAssetRoutes[i].assets[
                        toBaseAssetRoutes[i].swaps[0].assetInIndex
                    ]
                ) != rewardTokens[i]
            ) revert InvalidConfig();

            // Verify that the last token out is the baseAsset
            if (
                address(
                    toBaseAssetRoutes[i].assets[
                        toBaseAssetRoutes[i]
                            .swaps[toBaseAssetRoutes[i].swaps.length - 1]
                            .assetOutIndex
                    ]
                ) != baseAsset
            ) revert InvalidConfig();
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        address,
        BalancerRoute memory toAssetRoute,
        bytes memory optionalData
    ) internal virtual {
        // Verify base asset to asset path
        if (baseAsset != asset) {
            // Verify that the first token in is the baseAsset

            if (
                address(
                    toAssetRoute.assets[toAssetRoute.swaps[0].assetInIndex]
                ) != baseAsset
            ) revert InvalidConfig();

            // Verify that the last token out is the asset
            if (
                address(
                    toAssetRoute.assets[
                        toAssetRoute
                            .swaps[toAssetRoute.swaps.length - 1]
                            .assetOutIndex
                    ]
                ) != asset
            ) revert InvalidConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address vault,
            BalancerRoute[] memory toBaseAssetRoutes,
            BalancerRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    BalancerRoute[],
                    BalancerRoute,
                    uint256[],
                    bytes
                )
            );

        _approveRewards(vault);

        _setUpAsset(
            baseAsset,
            IAdapter(address(this)).asset(),
            vault,
            optionalData
        );
    }

    function _approveRewards(address vault) internal {
        // Approve all rewardsToken for trading
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();
        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20(rewardTokens[i]).approve(vault, type(uint256).max);
        }
    }

    function _setUpAsset(
        address baseAsset,
        address asset,
        address vault,
        bytes memory optionalData
    ) internal virtual {
        if (asset != baseAsset)
            IERC20(baseAsset).approve(vault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address baseAsset,
            address vault,
            BalancerRoute[] memory toBaseAssetRoutes,
            BalancerRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (
                    address,
                    address,
                    BalancerRoute[],
                    BalancerRoute,
                    uint256[],
                    bytes
                )
            );

        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapToBaseAsset(vault, toBaseAssetRoutes, minTradeAmounts);

        _getAsset(baseAsset, asset, vault, toAssetRoute, optionalData);

        uint256 depositAmount = IERC20(asset).balanceOf(address(this)) -
            balBefore;

        // Deposit new assets into adapter
        if (depositAmount > 0)
            IAdapter(address(this)).strategyDeposit(depositAmount, 0);

        emit Harvest();
    }

    function _swapToBaseAsset(
        address vault,
        BalancerRoute[] memory toBaseAssetRoutes,
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
                toBaseAssetRoutes[i].swaps[0].amount = rewardBal;
                IBalancerVault(vault).batchSwap(
                    SwapKind.GIVEN_IN,
                    toBaseAssetRoutes[i].swaps,
                    toBaseAssetRoutes[i].assets,
                    FundManagement(
                        address(this),
                        false,
                        payable(address(this)),
                        false
                    ),
                    toBaseAssetRoutes[i].limits,
                    block.timestamp
                );
            }
        }
    }

    function _getAsset(
        address baseAsset,
        address asset,
        address vault,
        BalancerRoute memory toAssetRoute,
        bytes memory optionalData
    ) internal virtual {
        // Trade base asset for asset
        if (asset != baseAsset) {
            toAssetRoute.swaps[0].amount = IERC20(baseAsset).balanceOf(
                address(this)
            );

            IBalancerVault(vault).batchSwap(
                SwapKind.GIVEN_IN,
                toAssetRoute.swaps,
                toAssetRoute.assets,
                FundManagement(
                    address(this),
                    false,
                    payable(address(this)),
                    false
                ),
                toAssetRoute.limits,
                block.timestamp
            );
        }
    }
}
