// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {BaseStrategy} from "./BaseStrategy.sol";
import {IBaseAdapter} from "./interfaces/IBaseAdapter.sol";

abstract contract BaseCompounder is BaseStrategy {
    IERC20 internal baseAsset;
    uint256[] internal minTradeAmounts;
    bool internal depositLpToken;

    // TODO allow owner to change minTradeAmounts, autoHarvest?

    function __BaseCompounder_init(
        bool _autoHarvest,
        bytes memory _harvestData,
        IERC20 _baseAsset,
        uint256[] memory _minTradeAmounts,
        bool _depositLpToken
    ) internal {
        __BaseStrategy_init(_autoHarvest, _harvestData);

        baseAsset = _baseAsset;
        minTradeAmounts = _minTradeAmounts;
        depositLpToken = _depositLpToken;
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function harvest(bytes memory optionalData) external virtual override {
        _harvest(optionalData);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(
        bytes memory optionalData
    ) internal virtual override {
        _compound(optionalData);
    }

    function _compound(bytes memory optionalData) internal {
        // Claim Rewards from Adapter
        IBaseAdapter(address(this))._claimRewards();

        // Swap Rewards to BaseAsset (which can but must not be the underlying asset)
        _swapToBaseAsset(optionalData);

        // Stop compounding if the trades were not successful
        if (baseAsset.balanceOf(address(this)) == 0) {
            return;
        }

        // Get the underlying asset if the baseAsset is not the underlying asset
        _getAsset(optionalData);

        // Deposit the underlying asset into the adapter
        depositLpToken
            ? IBaseAdapter(address(this))._depositLP(
                IERC20(IBaseAdapter(address(this)).lpToken()).balanceOf(
                    address(this)
                )
            )
            : IBaseAdapter(address(this))._depositUnderlying(
                IERC20(IBaseAdapter(address(this)).underlying()).balanceOf(
                    address(this)
                )
            );
    }

    /// @dev This function gets called for each rewardToken to trade it to a base asset. 
    /// @dev The base asset can be the underlying token but can also be an unrelated token.
    /// @dev The differentiation between baseAsset and asset exists to allow for more efficient trade paths
    ///      (reward1 -> baseAsset, reward2 -> baseAsset, baseAsset -> asset) instead of (reward1 -> baseAsset -> asset, reward2 -> baseAsset -> asset)
    function _swapToBaseAsset(bytes memory optionalData) internal virtual {}
    
    /// @dev This function trades the baseAsset for the underlying asset if the baseAsset is not the underlying asset.
    function _getAsset(bytes memory optionalData) internal virtual {}
}
