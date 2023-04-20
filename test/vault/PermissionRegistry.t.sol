// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import { Test } from "forge-std/Test.sol";
import { PermissionRegistry, Permission } from "../../src/vault/PermissionRegistry.sol";

contract PermissionRegistryTest is Test {
  PermissionRegistry registry;

  address nonOwner = address(0x666);
  address target1 = address(0x1111);
  address target2 = address(0x2222);

  address[] targets;
  Permission[] newPermissions;

  event PermissionSet(address target, bool newEndorsement, bool newRejection);

  function setUp() public {
    registry = new PermissionRegistry(address(this));
  }

  /*//////////////////////////////////////////////////////////////
                          ENDORSEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

  function test__setPermissions() public {
    targets.push(target1);
    newPermissions.push(Permission({ endorsed: true, rejected: false }));
    vm.expectEmit(true, true, true, false, address(registry));
    emit PermissionSet(target1, true, false);
    registry.setPermissions(targets, newPermissions);

    assertTrue(registry.endorsed(target1));
    assertFalse(registry.rejected(target1));

    targets.push(target2);
    newPermissions.push(Permission({ endorsed: false, rejected: true }));

    vm.expectEmit(true, true, true, false, address(registry));
    emit PermissionSet(target1, true, false);
    vm.expectEmit(true, true, true, false, address(registry));
    emit PermissionSet(target2, false, true);
    registry.setPermissions(targets, newPermissions);

    // Target1
    assertTrue(registry.endorsed(target1));
    assertFalse(registry.rejected(target1));
    // Target2
    assertFalse(registry.endorsed(target2));
    assertTrue(registry.rejected(target2));
  }

  function testFail__setPermissions_array_mismatch() public {
    targets.push(target1);
    registry.setPermissions(targets, newPermissions);
  }

  function testFail__setPermissions_endorsement_rejection_mismatch() public {
    targets.push(target1);
    newPermissions.push(Permission({ endorsed: true, rejected: true }));

    registry.setPermissions(targets, newPermissions);
  }

  function testFail__setPermissions_nonOwner() public {
    targets.push(target1);
    newPermissions.push(Permission({ endorsed: false, rejected: true }));

    vm.prank(nonOwner);
    registry.setPermissions(targets, newPermissions);
  }
}
