// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

/// @notice Enforces that the caller is the strategy via delegatecall
contract OnlyStrategy {
  error NotStrategy(address sender);

  modifier onlyStrategy() {
    if (msg.sender != address(this)) revert NotStrategy(msg.sender);
    _;
  }
}
