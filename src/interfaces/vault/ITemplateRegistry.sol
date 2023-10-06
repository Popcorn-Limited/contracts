// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

/// @notice Template used for creating new clones
struct Template {
  /// @Notice Cloneable implementation address
  address implementation;
  /// @Notice implementations can only be cloned if endorsed
  bool endorsed;
  /// @Notice Optional - Metadata CID which can be used by the frontend to add informations to a vault/adapter...
  string metadataCid;
  /// @Notice If true, the implementation will require an init data to be passed to the clone function
  bool requiresInitData;
  /// @Notice Optional - Address of an registry which can be used in an adapter initialization
  address registry;
  /// @Notice Optional - Only used by Strategies. EIP-165 Signatures of an adapter required by a strategy
  bytes4[8] requiredSigs;
}

interface ITemplateRegistry is IOwned {


  function templates(bytes32 templateCategory, bytes32 templateId) external view returns (Template memory);

  function getTemplate(bytes32 version, bytes32 category) external view returns (address);

  function addTemplate(bytes32 version, bytes32 category, address template) external;

  function addTemplateCategory(bytes32 templateCategory) external;
}
