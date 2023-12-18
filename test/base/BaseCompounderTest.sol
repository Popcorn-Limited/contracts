// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseHelperTest} from "./BaseHelperTest.sol";

abstract contract BaseCompounderTest is BaseHelperTest {
  
    /*//////////////////////////////////////////////////////////////
                              MIN TRADE AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function test__setMinTradeAmounts() public virtual {}

    function test__setMinTradeAmountsOnlyOwner() public virtual {}
}
