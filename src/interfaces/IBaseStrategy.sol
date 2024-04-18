// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IOwned} from "../IOwned.sol";
import {IERC4626} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IPermit} from "../IPermit.sol";
import {IPausable} from "../IPausable.sol";

interface IBaseStrategy is IERC4626, IOwned, IPermit, IPausable {
    function setPerformanceFee(uint256 fee) external;

    function performanceFee() external view returns (uint256);

    function highWaterMark() external view returns (uint256);

    function accruedPerformanceFee() external view returns (uint256);

    function harvest() external;

    function toggleAutoHarvest() external;

    function autoHarvest() external view returns (bool);

    function lastHarvest() external view returns (uint256);

    function harvestCooldown() external view returns (uint256);

    function setHarvestCooldown(uint256 harvestCooldown) external;

    function initialize(
        bytes memory adapterBaseData,
        address externalRegistry,
        bytes memory adapterData
    ) external;

    function decimals() external view returns (uint8);

    function decimalOffset() external view returns (uint8);
}
