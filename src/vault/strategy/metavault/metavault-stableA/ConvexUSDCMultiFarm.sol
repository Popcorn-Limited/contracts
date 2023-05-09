// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {StableABase, ERC20} from "./StableABase.sol";
import {IUniswapRouterV2} from "../../../../interfaces/external/uni/IUniswapRouterV2.sol";
import {IUniswapV2Pair} from "../../../../interfaces/external/uni/IUniswapV2Pair.sol";
import {IUniswapV2Module} from "../../../../interfaces/modules/IUniswapV2Module.sol";

contract ConvexUSDCMultiFarm is StableABase {
    constructor(
        address _native,
        address _assetToken,
        address[] memory _tradeModules,
        address[] memory _routers,
        address _vault,
        address _strategist,
        ProtocolAddress[] memory _protocolAddresses,
        ProtocolUint[] memory _protocolUints,
        address[][] memory _rewardsToNativeRoutes,
        address[] memory _nativeToAssetTokenRoute
    ) {
        native = _native;

        tradeModules = _tradeModules;
        routers = _routers;

        vault = _vault;
        strategist = _strategist;

        for (uint i; i < _protocolAddresses.length; ++i) {
            protocolAddresses[i] = _protocolAddresses[i];
        }

        for (uint i; i < _protocolUints.length; ++i) {
            protocolUints[i] = _protocolUints[i];
        }

        rewardsToNativeRoutes = _rewardsToNativeRoutes;
        nativeToAssetTokenRoute = _nativeToAssetTokenRoute;

        _setUp(rewardsToNativeRoutes, nativeToAssetTokenRoute, _assetToken);
    }

    /*//////////////////////////////////////////////////////////////
                          SETUP
    //////////////////////////////////////////////////////////////*/

    // Give allowances for protocol deposit and rewardToken swaps.
    function _giveAllowances() internal override {}

    /*//////////////////////////////////////////////////////////////
                          COMPOUND LOGIC
    //////////////////////////////////////////////////////////////*/

    // Swap all rewards to native token
    function _swapRewardsToNative(
        address[] memory _rewardRoute,
        uint256 _rewardAmount
    ) internal override {
        IUniswapV2Module uniV2Module = IUniswapV2Module(tradeModules[0]);
        address uniV2Router = routers[0];

        uniV2Module.swap(uniV2Router, _rewardRoute, _rewardAmount);
    }

    // Swap native tokens for lpTokens
    function _swapNativeToAssetToken() internal override {
        IUniswapV2Module uniV2Module = IUniswapV2Module(tradeModules[0]);
        address uniV2Router = routers[0];

        uniV2Module.swap(
            uniV2Router,
            nativeToAssetTokenRoute,
            ERC20(native).balanceOf(address(this))
        );
    }

    // Return available rewards for all rewardTokens.
    function rewardsAvailable() public override returns (uint256[] memory) {}
}
