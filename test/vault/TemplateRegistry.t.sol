// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { TemplateRegistry } from "../../src/vault/TemplateRegistry.sol";

contract TemplateRegistryTest is Test {
  TemplateRegistry registry;

  address nonOwner = address(0x666);
  bytes32 templateCategory = "vault";
  bytes32 version = "0xv1";

  address[] addressArray;

  function setUp() public {
    registry = new TemplateRegistry(address(this));
  }

  /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

  function addTemplate(address implementation) public {
    registry.addTemplate(
      version,
      templateCategory,
      implementation
    );
  }

  /*//////////////////////////////////////////////////////////////
                          ADD TEMPLATE
    //////////////////////////////////////////////////////////////*/

  function test__addTemplate() public {
    address template = vm.addr(1238);
    registry.addTemplate(
      version,
      templateCategory,
      template
    );
    assertTrue(registry.templateExists(version, template));
  }

  function testFail__addTemplate_template_already_exists() public {
    address template = vm.addr(1238);
    addTemplate(template);

    vm.expectRevert(TemplateRegistry.TemplateExists(version, template));
    registry.addTemplate(
      version,
      templateCategory,
      template
    );
  }

  function test__removeTemplate() public {
    address template = vm.addr(1238);
    addTemplate(template);

    registry.removeTemplate(version, templateCategory, template);
  } 
}
