// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {BalancerUtils, IBalancerVault} from "./BalancerUtils.sol";
import {IGauge, IMinter, IController} from "../../../adapter/balancer/IBalancer.sol";

contract BalancerLpCompounder is StrategyBase {
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
            bytes32[] memory _poolIds,
            uint256[] memory _assetInIndexes,
            uint256[] memory _assetOutIndexes,
            uint256[] memory _amountsIn,
            address[] memory _assets,
            address[] memory toBaseAssetPaths,
            address[] memory toAssetPaths,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    bytes32[],
                    uint256[],
                    uint256[],
                    uint256[],
                    address[],
                    bytes
                )
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
        bytes32[] memory _poolIds,
        address baseAsset
    ) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            // Route[] memory route = toBaseAssetPaths[i];
            // if (
            //     route[0].from != rewardTokens[i] ||
            //     route[route.length - 1].to != baseAsset
            // ) revert InvalidConfig();
        }
    }

    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes32[] memory _poolIds,
        bytes memory
    ) internal virtual {
        // Verify base asset to asset path
        // ILpToken lpToken = ILpToken(asset);
        // Route[] memory toLp0Route = toAssetPaths[0];
        // if (toLp0Route[0].from != baseAsset) revert InvalidConfig();
        // if (toLp0Route[toLp0Route.length - 1].to != lpToken.token0())
        //     revert InvalidConfig();
        // if (toAssetPaths.length > 1) {
        //     Route[] memory toLp1Route = toAssetPaths[1];
        //     if (toLp1Route[0].from != baseAsset) revert InvalidConfig();
        //     if (toLp1Route[toLp1Route.length - 1].to != lpToken.token1())
        //         revert InvalidConfig();
        // }
    }

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp(bytes memory data) public override {
        (
            address baseAsset,
            address router,
            bytes32[] memory _poolIds,
            uint256[] memory _assetInIndexes,
            uint256[] memory _assetOutIndexes,
            uint256[] memory _amountsIn,
            address[] memory _assets,
            address[] memory toBaseAssetPaths,
            address[] memory toAssetPaths,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    bytes32[],
                    uint256[],
                    uint256[],
                    uint256[],
                    address[],
                    bytes
                )
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
    }

    /*//////////////////////////////////////////////////////////////
                          HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    // Harvest rewards.
    function harvest() public override {
        (
            address _baseAsset,
            address _router,
            bytes32[] memory _poolIds,
            uint256[] memory _assetInIndexes,
            uint256[] memory _assetOutIndexes,
            uint256[] memory _amountsIn,
            address[] memory _assets,
            address[] memory _toBaseAssetPaths,
            address[] memory _toAssetPaths,
            bytes memory _optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (
                    address,
                    address,
                    bytes32[],
                    uint256[],
                    uint256[],
                    uint256[],
                    address[],
                    bytes
                )
            );

        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapToBaseAsset(_router, _toBaseAssetPaths, _amountsIn);

        _getAsset(_baseAsset, asset, _router, _toAssetPaths, _optionalData);

        // Deposit new assets into adapter
        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _swapToBaseAsset(
        address _router,
        bytes32[] memory _poolIds,
        uint256[] memory _assetInIndexes,
        uint256[] memory _assetOutIndexes,
        uint256[] memory _amountsIn,
        address[] memory _assets,
        bytes[] memory _toBaseAssetPaths
    ) internal {
        // Trade rewards for base asset
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardBal = IERC20(rewardTokens[i]).balanceOf(
                address(this)
            );
            if (rewardBal >= _amountsIn[i]) {
                BalancerUtils.swap(
                    _router,
                    _poolIds,
                    _assetInIndexes,
                    _assetOutIndexes,
                    _amountsIn,
                    _assets
                );
            }
        }
    }

    function _getAsset(
        address _router,
        address _baseAsset,
        bytes32[] memory _poolIds,
        uint256[] memory _assetInIndexes,
        uint256[] memory _assetOutIndexes,
        uint256[] memory _amountsIn,
        address[] memory _assets,
        bytes memory optionalData
    ) internal virtual {
        uint256 lp0Amount = IERC20(_baseAsset).balanceOf(address(this)) / 2;
        BalancerUtils.swap(
            _router,
            _poolIds,
            _assetInIndexes,
            _assetOutIndexes,
            _amountsIn,
            _assets
        );

        ILpToken LpToken = ILpToken(asset);

        address tokenA = LpToken.token0();
        address tokenB = LpToken.token1();
        uint256 amountA = IERC20(tokenA).balanceOf(address(this));
        uint256 amountB = IERC20(tokenB).balanceOf(address(this));

        IBalancerRouter(router).addLiquidity(
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
