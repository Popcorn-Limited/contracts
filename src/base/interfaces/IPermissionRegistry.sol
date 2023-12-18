// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IOwned } from "./IOwned.sol";

interface IPermissionRegistry {
  function setEndorsements(address[] calldata targets, bool[] calldata endorsements) external;
  function endorsed(address target) external view returns (bool);
}
