// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest, BalancerRoute, IAdapter, BalancerCompounder, ERC4626, ERC20, IERC20} from "./BalancerCompounder.sol";

contract BalancerLpCompounder is BalancerCompounder {
    /*//////////////////////////////////////////////////////////////
                          VERIFICATION
    //////////////////////////////////////////////////////////////*/

    event log_uint(uint256);

    function _verifyAsset(
        address baseAsset,
        address asset,
        address vault,
        BalancerRoute memory toAssetRoute,
        bytes memory optionalData
    ) internal override {
        (bytes32 poolId, uint8 indexIn) = abi.decode(
            optionalData,
            (bytes32, uint8)
        );

        // Verify that the lpToken matches the asset
        (address lpToken, ) = IBalancerVault(vault).getPool(poolId);
        if (lpToken != asset) revert InvalidConfig();

        address depositToken = baseAsset;
        if (toAssetRoute.assets.length > 0) {
            if (
                address(
                    toAssetRoute.assets[toAssetRoute.swaps[0].assetInIndex]
                ) != baseAsset
            ) revert InvalidConfig();

            depositToken = address(
                toAssetRoute.assets[
                    toAssetRoute
                        .swaps[toAssetRoute.swaps.length - 1]
                        .assetOutIndex
                ]
            );
        }

        // Verify that our deposit token is in the pool
        (address[] memory underlyings, , ) = IBalancerVault(vault)
            .getPoolTokens(poolId);
        if (underlyings[indexIn] != depositToken) revert InvalidConfig();
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    function _getAsset(
        address baseAsset,
        address asset,
        address vault,
        BalancerRoute memory toAssetRoute,
        bytes memory optionalData
    ) internal override {
        (bytes32 poolId, uint8 indexIn) = abi.decode(
            optionalData,
            (bytes32, uint8)
        );
        (address[] memory underlyings, , ) = IBalancerVault(vault)
            .getPoolTokens(poolId);
        address depositToken = underlyings[indexIn];

        if (depositToken != baseAsset) {
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

        uint256[] memory amounts = new uint256[](underlyings.length);
        amounts[indexIn] = IERC20(depositToken).balanceOf(address(this));

        IBalancerVault(vault).joinPool(
            poolId,
            address(this),
            address(this),
            JoinPoolRequest(
                underlyings,
                amounts,
                abi.encode(1, amounts, 0), // Exact In Enum, inAmounts, minOut
                false
            )
        );
    }
}
