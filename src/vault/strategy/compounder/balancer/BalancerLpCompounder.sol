// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {BalancerUtils, IBalancerVault, SwapKind, BatchSwapStep, BatchSwapStruct, FundManagement, IAsset} from "./BalancerUtils.sol";
import {IGauge, IMinter, IController} from "../../../adapter/balancer/IBalancer.sol";

// TODO - update imports

contract BalancerLpCompounder is BalancerCompounder {
    // Events
    event Harvest();

    // Errors
    error InvalidConfig();

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION
    //////////////////////////////////////////////////////////////*/

    function _verifyAsset(
        address baseAsset,
        address asset,
        BalancerRoute toAssetRoute,
        bytes memory optionalData
    ) internal virtual {
        // TODO - encode everything needed to make a pool call in optionalData
        // TODO - make sure the assetIn of the poolCall === baseAsset
        // TODO - make sure that the assetOut of the poolCall === asset
        
        if (
            toAssetRoute.assets[toAssetRoute.swaps[0].assetInIndex] != baseAsset
        ) revert InvalidConfig();

        // Verify that the last token out is the asset
        if (
            toAssetRoute.assets[
                toAssetRoute.swaps[toAssetRoute.swaps.length - 1].assetOutIndex
            ] != asset
        ) revert InvalidConfig();
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function _setUpAsset(
        address baseAsset,
        address asset,
        address vault,
        bytes memory optionalData
    ) internal virtual {
        // TODO - do we even need to change something here? or can we delete it?
        if (asset != baseAsset)
            IERC20(baseAsset).approve(vault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    function _getAsset(
        address baseAsset,
        address asset,
        address vault,
        BalancerRoute[] memory toAssetRoute,
        bytes memory optionalData
    ) internal virtual {
        // TODO - encode everything needed to make a pool call in optionalData
        // TODO - construct the pool call using baseAsset
        // TODO - make the pool call

        toAssetRoute.swaps.amount = IERC20(baseAsset).balanceOf(address(this));

        JoinPoolRequest memory request = JoinPoolRequest(
            _lpTokens,
            amounts,
            userData,
            false
        );
    }
}
