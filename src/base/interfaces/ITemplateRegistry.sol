// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IOwned } from "./IOwned.sol";

interface ITemplateRegistry is IOwned {
  function templates(bytes32 version, address template) external view returns (bool);
  function allTemplates(bytes32 version, bytes32 category) external view returns (address[] memory);
  function addTemplate(
    bytes32 version,
    bytes32 category,
    address template
  ) external;

  function removeTemplate(
    bytes32 version,
    bytes32 category,
    address template
  ) external;
}
