// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { VaultRegistry } from "../../src/vault/VaultRegistry.sol";
import { VaultMetadata } from "../../src/interfaces/vault/IVaultRegistry.sol";
import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { MockERC4626, IERC20 } from "../utils/mocks/MockERC4626.sol";

contract VaultRegistryTest is Test {
  MockERC20 asset = new MockERC20("ERC20", "TEST", 18);
  MockERC4626 vault;
  VaultRegistry registry;

  address nonOwner = makeAddr("non owner");

  address staking = makeAddr("staking");
  address creator = makeAddr("creator");
  address swapAddress = makeAddr("swap address");

  string constant metadataCid = "QmbWqxBEKC3P8tqsKc98xmWNzrzDtRLMiMPL8wBuTGsMnR";
  address[8] swapTokenAddresses;

  event VaultAdded(address vault, string metadataCID);

  function setUp() public {
    for (uint256 i; i < 8; ++i) {
      swapTokenAddresses[i] = address(uint160(i));
    }

    vault = new MockERC4626();
    vault.initialize(IERC20(address(asset)), "ERC4626", "TEST-4626");

    registry = new VaultRegistry(address(this));
  }

  /*//////////////////////////////////////////////////////////////
                          REGISTER_VAULT
    //////////////////////////////////////////////////////////////*/
  function test__registerVault() public {
    VaultMetadata memory VaultInitParams = VaultMetadata({
      vault: address(vault),
      staking: staking,
      creator: creator,
      metadataCID: metadataCid,
      swapTokenAddresses: swapTokenAddresses,
      swapAddress: swapAddress,
      exchange: 1
    });

    vm.expectEmit(false, false, false, true);
    emit VaultAdded(address(vault), metadataCid);

    registry.registerVault(VaultInitParams);

    VaultMetadata memory savedVault = registry.getVault(address(vault));

    assertEq(savedVault.vault, address(vault));
    assertEq(savedVault.staking, staking);
    assertEq(savedVault.creator, creator);
    assertEq(savedVault.metadataCID, metadataCid);
    assertEq(savedVault.swapAddress, swapAddress);
    assertEq(savedVault.exchange, 1);

    for (uint256 i; i < 8; ++i) {
      assertEq(savedVault.swapTokenAddresses[i], address(uint160(i)));
    }
  }

  function test__registerVault_nonOwner() public {
    VaultMetadata memory VaultInitParams = VaultMetadata({
      vault: address(vault),
      staking: staking,
      creator: creator,
      metadataCID: metadataCid,
      swapTokenAddresses: swapTokenAddresses,
      swapAddress: swapAddress,
      exchange: 1
    });

    vm.prank(nonOwner);
    vm.expectRevert("Only the contract owner may perform this action");
    registry.registerVault(VaultInitParams);
  }

  function test__registerVault_vault_already_registered() public {
    VaultMetadata memory VaultInitParams = VaultMetadata({
      vault: address(vault),
      staking: staking,
      creator: creator,
      metadataCID: metadataCid,
      swapTokenAddresses: swapTokenAddresses,
      swapAddress: swapAddress,
      exchange: 1
    });

    registry.registerVault(VaultInitParams);

    vm.expectRevert(VaultRegistry.VaultAlreadyRegistered.selector);
    registry.registerVault(VaultInitParams);
  }
}
