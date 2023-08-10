// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BeefyAdapter, IERC20} from "./BeefyAdapter.sol";
import {CurveCompounder, CurveRoute} from "./CurveCompounder.sol";

contract BeefyCompounder is BeefyAdapter, CurveCompounder {
    // TODO pack these variables better
    function initialize(
        IERC20 _underlying,
        IERC20 _lpToken,
        bool _useLpToken,
        IERC20[] memory _rewardTokens,
        address _registry,
        bytes memory _beefyInitData,
        bool _autoHarvest,
        bytes memory _harvestData,
        IERC20 _baseAsset,
        uint256[] memory _minTradeAmounts,
        bool _depositLpToken,
        CurveRoute[] memory _toBaseAssetRoutes,
        CurveRoute memory _toAssetRoute,
        address _router
    ) external onlyInitializing {
        __BeefyAdapter_init(
            _underlying,
            _lpToken,
            _useLpToken,
            _rewardTokens,
            _registry,
            _beefyInitData
        );
        __CurveCompounder_init(
            _autoHarvest,
            _harvestData,
            _baseAsset,
            _minTradeAmounts,
            _depositLpToken,
            _toBaseAssetRoutes,
            _toAssetRoute,
            _router
        );
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        if (autoHarvest) _harvest(harvestData);
        _deposit(amount);
    }

    function withdraw(uint256 amount) external override onlyVault {
        if (!paused() && autoHarvest) _harvest(harvestData);
        _withdraw(amount);
    }

    function _compound(bytes memory optionalData) internal override {
        // Claim Rewards from Adapter
        _claimRewards();

        // Swap Rewards to BaseAsset (which can but must not be the underlying asset)
        _swapToBaseAsset(rewardTokens, optionalData);

        // Stop compounding if the trades were not successful
        if (baseAsset.balanceOf(address(this)) == 0) {
            return;
        }

        // Get the underlying asset if the baseAsset is not the underlying asset
        _getAsset(optionalData);

        // Deposit the underlying asset into the adapter
        depositLpToken
            ? _depositLP(lpToken.balanceOf(address(this)))
            : _depositUnderlying(underlying.balanceOf(address(this)));
    }
}
