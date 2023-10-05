// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IOwned } from "../IOwned.sol";

struct VaultMetadata {
  /// @notice Vault address
  address vault;
  /// @notice Category of vault deployed e.g (SINGLE_STRATEGY VAULT or REBALANCING VAULT)
  bytes32 vaultCategory;
  /// @notice Owner and Vault creator
  address creator;
}

interface IVaultRegistry is IOwned {
  function getVault(address vault) external view returns (VaultMetadata memory);

  function getSubmitter(address vault) external view returns (address);

  function registerVault(VaultMetadata memory metadata) external;
}
