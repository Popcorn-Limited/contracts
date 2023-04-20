// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IWithRewards } from "../../interfaces/vault/IWithRewards.sol";
import { IEIP165 } from "../../interfaces/IEIP165.sol";

contract StrategyBase {
  error FunctionNotImplemented(bytes4 sig);

  function verifyAdapterSelectorCompatibility(bytes4[8] memory sigs) public {
    uint8 len = uint8(sigs.length);
    for (uint8 i; i < len; i++) {
      if (sigs[i].length == 0) return;
      if (!IEIP165(address(this)).supportsInterface(sigs[i])) revert FunctionNotImplemented(sigs[i]);
    }
  }

  function verifyAdapterCompatibility(bytes memory data) public virtual {}

  function setUp(bytes memory data) public virtual {}

  function harvest() public virtual {}
}
