// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

interface ITemplateRegistry is IOwned {
<<<<<<< HEAD


  function templates(bytes32 templateCategory, bytes32 templateId) external view returns (Template memory);

  function getTemplate(bytes32 version, bytes32 category) external view returns (address);

  function addTemplate(bytes32 version, bytes32 category, address template) external;

  function addTemplateCategory(bytes32 templateCategory) external;
=======
  function templates(bytes32 version, address template) external view returns (bool);
  function allTemplates(bytes32 version, bytes32 category) external view returns (address[] memory;)
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
>>>>>>> 55f9d4f (fix(VaultFactory): use correct interface for TemplateRegistry)
}
