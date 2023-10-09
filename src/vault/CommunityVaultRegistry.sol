// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "../utils/Owned.sol";

/**
 * @title   VaultRegistry
 * @author  RedVeil
 * @notice  Registers vaults with metadata for use by a frontend.
 */
contract VaultRegistry is Owned {
  mapping(address => bool) public factories;

  /// @param _owner `VaultFactory`
  constructor(address _owner) Owned(_owner) {}

  function addFactory(address factory) external onlyOwner {
    factories[factory] = true;
  }

  function removeFactory(address factory) external onlyOwner {
    factories[factory] = false;
  }

  /*//////////////////////////////////////////////////////////////
                            REGISTRATION LOGIC
  //////////////////////////////////////////////////////////////*/

  error NotFactory();

  modifier onlyFactory() {
    if (!factories[msg.sender]) revert NotFactory();
    _;
  }

  // easy way to check whether a given address is a vault
  mapping(address => bool) public vaults;

  // addresses of all registered vaults
  address[] public allVaults;

  event VaultAdded(
    address indexed vault,
    address indexed creator
  );

  error VaultAlreadyRegistered();

  /**
   * @notice Registers a new vault with Metadata which can be used by a frontend. Caller must be owner. (`VaultController`)
   * @param vault the vault's address
   * @param creator the vault's creator
   */
  function registerVault(address vault, address creator) external onlyFactory {
    if (vaults[vault]) revert VaultAlreadyRegistered();

    vaults[vault] = true;
    allVaults.push(vault);

    emit VaultAdded(vault, creator);
  }

  function getTotalVaults() external view returns (uint256) {
    return allVaults.length;
  }

  function getRegisteredAddresses() external view returns (address[] memory) {
    return allVaults;
  }
}
