// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {BaseHelper, IOwned, HarvestConfig} from "./BaseHelper.sol";
import {IBaseAdapter} from "./interfaces/IBaseAdapter.sol";

struct CompounderConfig {
    IERC20 baseAsset;
    uint256[] minTradeAmounts;
    bool depositLpToken;
}

abstract contract BaseCompounder is BaseHelper {
    CompounderConfig internal compounderConfig;

    function __BaseCompounder_init(
        HarvestConfig memory _harvestConfig,
        CompounderConfig memory _compounderConfig
    ) internal {
        __BaseHelper_init(_harvestConfig);

        compounderConfig = _compounderConfig;
    }

    /*//////////////////////////////////////////////////////////////
                            HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards & executes the strategy
     */
    function harvest(bytes memory optionalData) external virtual override {
        _harvest(optionalData);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(bytes memory optionalData) internal virtual override {
        _compound(optionalData);
    }

    function _compound(bytes memory optionalData) internal {
        // Claim Rewards from Adapter
        _claimRewards();

        // Swap Rewards to BaseAsset (which can but must not be the underlying asset)
        _swapToBaseAsset(_getRewardTokens(), optionalData);

        // Stop compounding if the trades were not successful
        if (compounderConfig.baseAsset.balanceOf(address(this)) == 0) {
            return;
        }

        // Get the underlying asset if the baseAsset is not the underlying asset
        _getAsset(optionalData);

        _depositIntoAdapter();
    }

    /*//////////////////////////////////////////////////////////////
                        FUNCTIONS TO OVERRIDE
    //////////////////////////////////////////////////////////////*/

    function _claimRewards() internal virtual {}

    function _depositIntoAdapter() internal virtual {}

    function _getRewardTokens()
        internal
        view
        virtual
        returns (IERC20[] memory)
    {}

    /// @dev This function gets called for each rewardToken to trade it to a base asset.
    /// @dev The base asset can be the underlying token but can also be an unrelated token.
    /// @dev The differentiation between baseAsset and asset exists to allow for more efficient trade paths
    ///      (reward1 -> baseAsset, reward2 -> baseAsset, baseAsset -> asset) instead of (reward1 -> baseAsset -> asset, reward2 -> baseAsset -> asset)
    function _swapToBaseAsset(
        IERC20[] memory rewardTokens,
        bytes memory optionalData
    ) internal virtual {}

    /// @dev This function trades the baseAsset for the underlying asset if the baseAsset is not the underlying asset.
    function _getAsset(bytes memory optionalData) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setMinTradeAmounts(uint256[] memory _minTradeAmounts) external {
        require(
            msg.sender == IOwned(address(this)).owner(),
            "Only the contract owner may perform this action"
        );
        compounderConfig.minTradeAmounts = _minTradeAmounts;
    }
}
