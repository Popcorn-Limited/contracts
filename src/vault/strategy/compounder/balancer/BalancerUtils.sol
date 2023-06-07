// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "src/utils/Path.sol";
import {IERC20, IBalancerVault, SwapKind, BatchSwapStep, BatchSwapStruct, IAsset, FundManagement, JoinPoolRequest} from "../../../../interfaces/external/balancer/IBalancerVault.sol";
import {IGauge} from "src/vault/adapter/balancer/IBalancer.sol";

library BalancerUtils {
    using Path for bytes;

    function swap(
        address _vault,
        SwapKind _swapKind,
        BatchSwapStep[] memory _swaps,
        IAsset[] memory _tokens,
        FundManagement memory _funds,
        int256 _amountIn
    ) internal returns (int256[] memory) {
        int256[] memory limits = new int256[](_tokens.length);
        for (uint i; i < _tokens.length; ) {
            if (i == 0) {
                limits[0] = _amountIn;
            } else if (i == _tokens.length - 1) {
                limits[i] = -1;
            }
            unchecked {
                ++i;
            }
        }
        return
            IBalancerVault(_vault).batchSwap(
                _swapKind,
                _swaps,
                _tokens,
                _funds,
                limits,
                block.timestamp
            );
    }

    function buildSwapStructArray(
        BatchSwapStruct[] memory _route,
        uint256 _amountIn
    ) internal pure returns (BatchSwapStep[] memory) {
        BatchSwapStep[] memory swaps = new BatchSwapStep[](_route.length);
        for (uint i; i < _route.length; ) {
            if (i == 0) {
                swaps[0] = BatchSwapStep({
                    poolId: _route[0].poolId,
                    assetInIndex: _route[0].assetInIndex,
                    assetOutIndex: _route[0].assetOutIndex,
                    amount: _amountIn,
                    userData: ""
                });
            } else {
                swaps[i] = BatchSwapStep({
                    poolId: _route[i].poolId,
                    assetInIndex: _route[i].assetInIndex,
                    assetOutIndex: _route[i].assetOutIndex,
                    amount: 0,
                    userData: ""
                });
            }
            unchecked {
                ++i;
            }
        }

        return swaps;
    }

    function joinPool(
        address _vault,
        bytes32 _poolId,
        address _tokenIn,
        uint256 _amountIn
    ) internal {
        (IERC20[] memory lpTokens, , ) = IBalancerVault(_vault).getPoolTokens(
            _poolId
        );
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length; ) {
            amounts[i] = address(lpTokens[i]) == _tokenIn ? _amountIn : 0;
            unchecked {
                ++i;
            }
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IAsset[] memory _lpTokens = new IAsset[](lpTokens.length);
        for (uint256 i = 0; i < lpTokens.length; ++i) {
            _lpTokens[i] = IAsset(address(lpTokens[i]));
        }

        JoinPoolRequest memory request = JoinPoolRequest(
            _lpTokens,
            amounts,
            userData,
            false
        );
        IBalancerVault(_vault).joinPool(
            _poolId,
            address(this),
            address(this),
            request
        );
    }
}
