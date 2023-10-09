// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

interface IVaultRegistry is IOwned {
  function addFactory(address factory) external;
  function registerVault(address vault, address creator) external;
}
