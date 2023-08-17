// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BeefyAdapter, IERC20, AdapterConfig, ProtocolConfig} from "../../adapter/beefy/BeefyAdapter.sol";
import {CurveCompounder, CurveRoute, HarvestConfig, CompounderConfig} from "../../helper/CurveCompounder.sol";

contract BeefyCompounder is BeefyAdapter, CurveCompounder {
    
    function initialize(
        AdapterConfig memory _adapterConfig,
        ProtocolConfig memory _protocolConfig,
        HarvestConfig memory _harvestConfig,
        CompounderConfig memory _compounderConfig,
        address _router,
        CurveRoute[] memory _toBaseAssetRoutes,
        CurveRoute memory _toAssetRoute
    ) external initializer {
        __BeefyAdapter_init(_adapterConfig, _protocolConfig);
        __CurveCompounder_init(
            _harvestConfig,
            _compounderConfig,
            _router,
            _toBaseAssetRoutes,
            _toAssetRoute
        );
    }

    function deposit(uint256 amount) external override onlyVault whenNotPaused {
        HarvestConfig memory _harvestConfig = harvestConfig;
        if (_harvestConfig.autoHarvest) _harvest(_harvestConfig.harvestData);
        _deposit(amount);
    }

    function withdraw(uint256 amount, address receiver) external override onlyVault {
        HarvestConfig memory _harvestConfig = harvestConfig;
        if (!paused() && _harvestConfig.autoHarvest)
            _harvest(_harvestConfig.harvestData);
        _withdraw(amount, receiver);
    }

    function _claimRewards() internal override {
        _claim();
    }

    function _depositIntoAdapter() internal override {
        // Deposit the underlying asset into the adapter
        compounderConfig.depositLpToken
            ? _depositLP(lpToken.balanceOf(address(this)))
            : _depositUnderlying(underlying.balanceOf(address(this)));
    }

    function _getRewardTokens()
        internal
        view
        override
        returns (IERC20[] memory)
    {
        return rewardTokens;
    }
}
