// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IOwned} from "./interfaces/IOwned.sol";

struct HarvestConfig {
    /// @dev autoHarvest is defined in the strategy but called by the BaseAdapter on each deposit/withdraw
    bool autoHarvest;
    /// @dev HarvestData is optionalData for the harvest function
    bytes harvestData;
}

abstract contract BaseHelper {
    HarvestConfig internal harvestConfig;

    function __BaseHelper_init(HarvestConfig memory _harvestConfig) internal {
        harvestConfig = _harvestConfig;
    }

    /*//////////////////////////////////////////////////////////////
                            HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setHarvestConfig(HarvestConfig memory _harvestConfig) external {
        require(
            msg.sender == IOwned(address(this)).owner(),
            "Only the contract owner may perform this action"
        );
        harvestConfig = _harvestConfig;
    }
}
