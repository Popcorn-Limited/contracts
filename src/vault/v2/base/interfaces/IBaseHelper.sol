// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IBaseHelper {
    /**
     * @notice Claims rewards & executes the strategy
     */
    function harvest(bytes memory optionalData) external;

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(bytes memory memoryoptionalData) external;

    function autoHarvest() external view returns (bool);

    function harvestData() external view returns (bytes memory);
}
