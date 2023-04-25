// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";

import {IEIP165} from "../../../../interfaces/IEIP165.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {StrategyBase} from "../StrategyBase.sol";

import {IUniswapRouterV2} from "../../../../interfaces/external/uni/IUniswapRouterV2.sol";

contract StableABase is StrategyBase {
    using Math for uint256;

    // Tokens used
    address public assetToken;

    // Routes
    address[] public nativeToAssetTokenRoute;

    /*//////////////////////////////////////////////////////////////
                          SETUP
    //////////////////////////////////////////////////////////////*/

    // Setup for routes and allowances in constructor.
    function _setUp(
        address[][] memory _rewardToNativeRoutes,
        address[] memory _nativeToAssetTokenRoute,
        address _assetToken
    ) internal virtual {
        if (_nativeToAssetTokenRoute[0] != native) revert InvalidRoute();

        assetToken = _assetToken;

        if (
            _nativeToAssetTokenRoute[_nativeToAssetTokenRoute.length - 1] !=
            _assetToken
        ) revert InvalidRoute();

        _setRewardTokens(_rewardToNativeRoutes);

        _giveInitialAllowances();
    }

    /*//////////////////////////////////////////////////////////////
                          ROUTES
    //////////////////////////////////////////////////////////////*/

    // Set nativeToAssetToken.
    function setNativeToAssetTokenRoute(
        address[] calldata route
    ) public virtual vaultCheck {
        nativeToAssetTokenRoute = route;
    }

    /*//////////////////////////////////////////////////////////////
                          COMPOUND LOGIC
    //////////////////////////////////////////////////////////////*/

    // Logic to claim rewards, swap rewards to native, charge fees, swap native to lpTokens, add liquidity, and re-deposit.
    function _compound() internal virtual override {
        _claimRewards();
        _swapRewardsToNative();
        _swapNativeToAssetToken();
        _deposit();
    }

    // Swap native tokens for assetToken
    function _swapNativeToAssetToken() internal virtual {}
}
