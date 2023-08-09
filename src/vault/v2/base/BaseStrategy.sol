// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

abstract contract BaseStrategy {
    /// @dev autoHarvest is defined in the strategy but called by the BaseAdapter on each deposit/withdraw
    bool internal autoHarvest;
    /// @dev HarvestData is optionalData for the harvest function
    bytes internal harvestData;

    function __BaseStrategy_init(
        bool _autoHarvest,
        bytes memory _harvestData
    ) internal {
        autoHarvest = _autoHarvest;
        harvestData = _harvestData;
    }

    /**
     * @notice Claims rewards & executes the strategy
     * @dev harvest should be overriden to receive custom access control depending on each strategy. 
            Some might be purely permissionless others might have access control.
     */
    function harvest(bytes memory optionalData) external virtual {
        _harvest(optionalData);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(bytes memory optionalData) internal virtual {}
}
