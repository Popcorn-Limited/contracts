// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseStrategyTest} from "./BaseStrategyTest.sol";

abstract contract BaseHelperTest is BaseStrategyTest {
    /*//////////////////////////////////////////////////////////////
                              HARVEST
    //////////////////////////////////////////////////////////////*/

    /// @dev OPTIONAL -- Implement this if the strategy utilizes `harvest()`
    function test__harvest() public virtual {}

    /*//////////////////////////////////////////////////////////////
                              HARVEST CONFIG
    //////////////////////////////////////////////////////////////*/

    function test__setHarvestConfig() public virtual {}

    function test__setHarvestConfigOnlyOwner() public virtual {}
}
