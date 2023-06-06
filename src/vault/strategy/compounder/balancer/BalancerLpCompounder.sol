// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IAdapter} from "../../../../interfaces/vault/IAdapter.sol";
import {IWithRewards} from "../../../../interfaces/vault/IWithRewards.sol";
import {StrategyBase} from "../../StrategyBase.sol";
import {BalancerUtils, IBalancerVault, SwapKind, BatchSwapStep, BatchSwapStruct, FundManagement, IAsset} from "./BalancerUtils.sol";
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
            address _asset,
            address _baseAsset,
            address _vault,
            bytes32 _poolId,
            SwapKind _swapKind,
            BatchSwapStruct[] memory _route,
            FundManagement memory _funds,
            address[] memory _tokens,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    address,
                    bytes32,
                    SwapKind,
                    BatchSwapStruct[],
                    FundManagement,
                    address[],
                    address,
                    bytes
                )
            );

        _verifyRewardToken(_poolId, _baseAsset);

        _verifyAsset(
            _baseAsset,
            IAdapter(msg.sender).asset(),
            _vault,
            _poolId,
            optionalData
        );
    }

    function _verifyRewardToken(bytes32 _poolId, address _baseAsset) internal {
        // Verify rewardToken + paths
        address[] memory rewardTokens = IWithRewards(msg.sender).rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {}
    }

    function _verifyAsset(
        address _baseAsset,
        address _asset,
        address _vault,
        bytes32 _poolId,
        bytes memory
    ) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp(bytes memory data) public override {
        (
            address _asset,
            address _baseAsset,
            address _vault,
            bytes32 _poolId,
            SwapKind _swapKind,
            BatchSwapStruct[] memory _route,
            FundManagement memory _funds,
            address[] memory _tokens,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    address,
                    bytes32,
                    SwapKind,
                    BatchSwapStruct[],
                    FundManagement,
                    address[],
                    bytes
                )
            );

        _approveRewards(_vault);

        _setUpAsset(
            _baseAsset,
            IAdapter(address(this)).asset(),
            _vault,
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
            address _asset,
            address _baseAsset,
            address _vault,
            bytes32 _poolId,
            SwapKind _swapKind,
            BatchSwapStruct[] memory _route,
            FundManagement memory _funds,
            IAsset[] memory _tokens,
            bytes memory optionalData
        ) = abi.decode(
                IAdapter(address(this)).strategyConfig(),
                (
                    address,
                    address,
                    address,
                    bytes32,
                    SwapKind,
                    BatchSwapStruct[],
                    FundManagement,
                    IAsset[],
                    bytes
                )
            );

        address asset = IAdapter(address(this)).asset();

        uint256 balBefore = IERC20(asset).balanceOf(address(this));

        IWithRewards(address(this)).claim();

        _swapToBaseAsset(_vault, _swapKind, _route, _funds, _tokens);

        _getAsset(_baseAsset, _vault, _poolId);

        // Deposit new assets into adapter
        IAdapter(address(this)).strategyDeposit(
            IERC20(asset).balanceOf(address(this)) - balBefore,
            0
        );

        emit Harvest();
    }

    function _swapToBaseAsset(
        address _vault,
        SwapKind _swapKind,
        BatchSwapStruct[][] memory _toBaseAssetPaths,
        FundManagement memory _funds,
        IAsset[] memory _tokens
    ) internal {
        // Trade rewards for base asset
        address[] memory rewardTokens = IWithRewards(address(this))
            .rewardTokens();

        uint256 len = rewardTokens.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 rewardBal = IERC20(rewardTokens[i]).balanceOf(
                address(this)
            );
            if (rewardBal > 0) {
                BatchSwapStep[] memory swaps = BalancerUtils
                    .buildSwapStructArray(_toBaseAssetPaths[i], rewardBal);

                BalancerUtils.swap(
                    _vault,
                    _swapKind,
                    swaps,
                    _tokens,
                    _funds,
                    int256(rewardBal)
                );
            }
        }
    }

    function _getAsset(
        address _asset,
        address _baseAsset,
        address _vault,
        bytes32 _poolId
    ) internal virtual {
        uint256 amountIn = IERC20(_baseAsset).balanceOf(address(this));

        BalancerUtils.joinPool(_vault, _poolId, _baseAsset, amountIn);
    }
}
