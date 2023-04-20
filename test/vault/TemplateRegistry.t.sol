// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { TemplateRegistry, Template } from "../../src/vault/TemplateRegistry.sol";
import { ClonableWithInitData } from "../utils/mocks/ClonableWithInitData.sol";
import { ClonableWithoutInitData } from "../utils/mocks/ClonableWithoutInitData.sol";

contract TemplateRegistryTest is Test {
  TemplateRegistry registry;

  address nonOwner = address(0x666);
  bytes32 templateCategory = "templateCategory";
  bytes32 templateId = "ClonableWithInitData";
  string metadataCid = "cid";

  address[] addressArray;
  bytes4[8] reqSigs;
  event TemplateCategoryAdded(bytes32 templateCategory);
  event TemplateAdded(bytes32 templateCategory, bytes32 templateId, address implementation);
  event TemplateUpdated(bytes32 templateCategory, bytes32 templateId);
  event TemplateEndorsementToggled(
    bytes32 templateCategory,
    bytes32 templateId,
    bool oldEndorsement,
    bool newEndorsement
  );

  function setUp() public {
    registry = new TemplateRegistry(address(this));
    reqSigs[0] = bytes4(keccak256("rewardsToken()"));
  }

  /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

  function addTemplate(address implementation) public {
    registry.addTemplateCategory(templateCategory);
    registry.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: implementation,
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: reqSigs
      })
    );
  }

  /*//////////////////////////////////////////////////////////////
                        ADD TEMPLATE TYPE
    //////////////////////////////////////////////////////////////*/
  function test__addTemplateCategory() public {
    vm.expectEmit(true, true, true, false, address(registry));
    emit TemplateCategoryAdded(templateCategory);

    registry.addTemplateCategory(templateCategory);

    bytes32[] memory templateCategories = registry.getTemplateCategories();
    assertEq(templateCategories.length, 1);
    assertEq(templateCategories[0], templateCategory);
    assertTrue(registry.templateCategoryExists(templateCategory));
  }

  function testFail__addTemplateCategory_nonOwner() public {
    vm.prank(nonOwner);
    registry.addTemplateCategory(templateCategory);
  }

  function testFail__addTemplateCategory_templateCategory_already_exists() public {
    registry.addTemplateCategory(templateCategory);

    vm.expectRevert(TemplateRegistry.TemplateCategoryExists.selector);
    registry.addTemplateCategory(templateCategory);
  }

  /*//////////////////////////////////////////////////////////////
                          ADD TEMPLATE
    //////////////////////////////////////////////////////////////*/

  function test__addTemplate() public {
    registry.addTemplateCategory(templateCategory);
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();

    vm.expectEmit(true, true, true, false, address(registry));
    emit TemplateAdded(templateCategory, templateId, address(clonableWithInitData));

    registry.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: true,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: reqSigs
      })
    );

    Template memory template = registry.getTemplate(templateCategory, templateId);
    assertEq(template.implementation, address(clonableWithInitData));
    // Always set endorsed to false when adding a template
    assertEq(template.endorsed, false);
    assertEq(template.metadataCid, metadataCid);
    assertEq(template.requiresInitData, true);
    assertEq(template.registry, address(0x2222));
    assertEq(template.requiredSigs[0], reqSigs[0]);
    assertEq(template.requiredSigs[7], reqSigs[7]);

    bytes32[] memory templateIds = registry.getTemplateIds(templateCategory);
    assertEq(templateIds.length, 1);
    assertEq(templateIds[0], templateId);

    assertTrue(registry.templateExists(templateId));
  }

  function testFail__addTemplate_templateCategory_doesnt_exists() public {
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();

    registry.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: reqSigs
      })
    );
  }

  function testFail__addTemplate_template_already_exists() public {
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();
    addTemplate(address(clonableWithInitData));

    registry.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: reqSigs
      })
    );
  }

  /*//////////////////////////////////////////////////////////////
                    TOGGLE TEMPLATE ENDORSEMENT
    //////////////////////////////////////////////////////////////*/

  function test__toggleTemplateEndorsement() public {
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();
    addTemplate(address(clonableWithInitData));

    vm.expectEmit(true, true, true, false, address(registry));
    emit TemplateEndorsementToggled(templateCategory, templateId, false, true);

    registry.toggleTemplateEndorsement(templateCategory, templateId);

    Template memory template = registry.getTemplate(templateCategory, templateId);
    assertTrue(template.endorsed);
  }

  function testFail__toggleTemplateEndorsement_templateId_doesnt_exist() public {
    registry.toggleTemplateEndorsement(templateCategory, templateId);
  }

  function testFail__toggleTemplateEndorsement_nonOwner() public {
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();
    addTemplate(address(clonableWithInitData));

    vm.prank(nonOwner);
    registry.toggleTemplateEndorsement(templateCategory, templateId);
  }
}
