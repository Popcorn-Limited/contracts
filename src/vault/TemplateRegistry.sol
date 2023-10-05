// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";
import { Template } from "../interfaces/vault/ITemplateRegistry.sol";

/**
 * @title   TemplateRegistry
 * @author  RedVeil
 * @notice  Adds Templates to be used for creating new clones.
 *
 * Templates are used by the `CloneFactory` to create new clones.
 * Templates can be added permissionlessly via `DeploymentController`.
 * Templates can be endorsed by the DAO via `VaultController`.
 */
contract TemplateRegistry is Owned {
  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  /// @param _owner `AdminProxy`
  constructor(address _owner) Owned(_owner) {}

  /*//////////////////////////////////////////////////////////////
                          TEMPLATE LOGIC
    //////////////////////////////////////////////////////////////*/

  // keeps track of all the existing allTemplates given a version & category
  /// @dev version => category => template
  mapping(bytes32 => mapping(bytes32 => address[])) public allTemplates;
  // allows to check whether a template is registered or not.
  // version => template address => bool
  mapping(bytes32 => mapping(address => bool)) public templates;

  event TemplateAdded(bytes32 version, bytes32 category, address template);
  error TemplateExists(bytes32 version, address template);

  /**
   * @notice Adds a new template to the registry.
   * @param version the template version
   * @param category of the new template, i.e. vault or strategy
   * @param template the address of the deployed template contract
   */
  function addTemplate(bytes32 version, bytes32 category, address template) external onlyOwner {
    if (templates[version][template]) {
      revert TemplateExists(version, template);
    }
    // we don't add any checks whether a template is already registered or not because this is only callable
    // by an admin who should do the necessary checks off-chain.
    allTemplates[version][category].push(template);
    templates[version][template] = true;

    emit TemplateAdded(version, category, template);
  }

  function getTemplate(bytes32 version, bytes32 category) external view returns (address) {
    return allTemplates[version][category][0];
  }


  /**
  * @param version the template version
  * @param category of the new template, i.e. vault or strategy
  * @param template the address of the deployed template contract
  */
  function removeTemplate(bytes32 version, bytes32 category, address template) external onlyOwner {
    address[] memory templateList = allTemplates[version][category];
    uint length = templateList.length;
    for (uint i; i < length;) {
      if (templateList[i] == template) {
        allTemplates[version][category][i] = templateList[length - 1];
        allTemplates[version][category].pop();
        break;
      }
      unchecked {++i;}
    }

    templates[version][template] = false;
  }
}
