// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";
import { VaultMetadata } from "../interfaces/vault/IVaultRegistry.sol";
import { IERC4626Upgradeable as IERC4626 } from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

/**
 * @title   VaultRegistry
 * @author  RedVeil
 * @notice  Registers vaults with metadata for use by a frontend.
 */
contract VaultRegistry is Owned {
  /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  /// @param _owner `AdminProxy`
  constructor(address _owner) Owned(_owner) {}

  /*//////////////////////////////////////////////////////////////
                            REGISTRATION LOGIC
    //////////////////////////////////////////////////////////////*/

  // vault to metadata
  mapping(address => VaultMetadata) public metadata;

  // asset to vault addresses
  mapping(address => address[]) public vaultsByAsset;

  // addresses of all registered vaults
  address[] public allVaults;

  event VaultAdded(address vaultAddress, string metadataCID);

  error VaultAlreadyRegistered();

  /**
   * @notice Registers a new vault with Metadata which can be used by a frontend. Caller must be owner. (`VaultController`)
   * @param _metadata VaultMetadata (See IVaultRegistry for more details)
   */
  function registerVault(VaultMetadata calldata _metadata) external onlyOwner {
    if (metadata[_metadata.vault].vault != address(0)) revert VaultAlreadyRegistered();

    metadata[_metadata.vault] = _metadata;

    allVaults.push(_metadata.vault);
    vaultsByAsset[IERC4626(_metadata.vault).asset()].push(_metadata.vault);

    emit VaultAdded(_metadata.vault, _metadata.metadataCID);
  }

  /*//////////////////////////////////////////////////////////////
                            VAULT VIEWING LOGIC
    //////////////////////////////////////////////////////////////*/

  function getVault(address vault) external view returns (VaultMetadata memory) {
    return metadata[vault];
  }

  function getVaultsByAsset(address asset) external view returns (address[] memory) {
    return vaultsByAsset[asset];
  }

  function getTotalVaults() external view returns (uint256) {
    return allVaults.length;
  }

  function getRegisteredAddresses() external view returns (address[] memory) {
    return allVaults;
  }

  function getSubmitter(address vault) external view returns (VaultMetadata memory) {
    return metadata[vault];
  }
}
