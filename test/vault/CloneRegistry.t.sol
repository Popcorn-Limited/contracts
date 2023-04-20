// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { CloneRegistry } from "../../src/vault/CloneRegistry.sol";

contract CloneRegistryTest is Test {
  CloneRegistry registry;

  address nonOwner = makeAddr("non owner");
  address clone = makeAddr("clone");

  bytes32 templateCategory = "templateCategory";
  bytes32 templateId = "templateId";

  event CloneAdded(address clone);

  function setUp() public {
    registry = new CloneRegistry(address(this));
  }

  /*//////////////////////////////////////////////////////////////
                              ADD CLONE
    //////////////////////////////////////////////////////////////*/

  function test__addClone() public {
    assertEq(registry.cloneExists(clone), false);

    vm.expectEmit(false, false, false, true);
    emit CloneAdded(clone);

    registry.addClone(templateCategory, templateId, clone);

    assertEq(registry.cloneExists(clone), true);
    assertEq(registry.clones(templateCategory, templateId, 0), clone);
    assertEq(registry.allClones(0), clone);
  }

  function test__addClone_nonOwner() public {
    vm.prank(nonOwner);
    vm.expectRevert("Only the contract owner may perform this action");
    registry.addClone(templateCategory, templateId, clone);
  }
}
