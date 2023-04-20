// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";
import { CloneRegistry } from "../../src/vault/CloneRegistry.sol";
import { CloneFactory } from "../../src/vault/CloneFactory.sol";
import { TemplateRegistry, Template } from "../../src/vault/TemplateRegistry.sol";
import { ICloneRegistry } from "../../src/interfaces/vault/ICloneRegistry.sol";
import { ICloneFactory } from "../../src/interfaces/vault/ICloneFactory.sol";
import { ITemplateRegistry } from "../../src/interfaces/vault/ITemplateRegistry.sol";
import { IOwned } from "../../src/interfaces/IOwned.sol";
import { ClonableWithInitData } from "../utils/mocks/ClonableWithInitData.sol";
import { ClonableWithoutInitData } from "../utils/mocks/ClonableWithoutInitData.sol";
import { DeploymentController } from "../../src/vault/DeploymentController.sol";

contract DeploymentControllerTest is Test {
  ITemplateRegistry templateRegistry;
  ICloneRegistry cloneRegistry;
  ICloneFactory factory;
  DeploymentController controller;

  ClonableWithInitData clonableWithInitDataImpl;
  ClonableWithoutInitData clonableWithoutInitDataImpl;

  address nonOwner = makeAddr("non owner");
  address registry = makeAddr("registry");

  bytes32 templateCategory = "templateCategory";
  bytes32 templateId = "ClonableWithoutInitData";
  string metadataCid = "cid";
  bytes4[8] requiredSigs;
  address[] addressArray;

  event TemplateCategoryAdded(bytes32 templateCategory);
  event TemplateAdded(bytes32 templateCategory, bytes32 templateId, address implementation);
  event TemplateUpdated(bytes32 templateCategory, bytes32 templateId);
  event TemplateEndorsementToggled(
    bytes32 templateCategory,
    bytes32 templateId,
    bool oldEndorsement,
    bool newEndorsement
  );

  event Deployment(address indexed clone);

  event CloneAdded(address clone);

  function setUp() public {
    deployDependencies(address(this));
    deployDeploymentController(address(this));
    nominateDependencyOwner(address(this), address(controller));
    controller.acceptDependencyOwnership();

    clonableWithInitDataImpl = new ClonableWithInitData();
    clonableWithoutInitDataImpl = new ClonableWithoutInitData();
  }

  /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

  function deployDependencies(address owner) public {
    factory = ICloneFactory(address(new CloneFactory(owner)));
    cloneRegistry = ICloneRegistry(address(new CloneRegistry(owner)));
    templateRegistry = ITemplateRegistry(address(new TemplateRegistry(owner)));
  }

  function nominateDependencyOwner(address owner, address newOwner) public {
    vm.startPrank(owner);
    factory.nominateNewOwner(newOwner);
    cloneRegistry.nominateNewOwner(newOwner);
    templateRegistry.nominateNewOwner(newOwner);
    vm.stopPrank();
  }

  function deployDeploymentController(address owner) public {
    controller = new DeploymentController(owner, factory, cloneRegistry, templateRegistry);
  }

  function addTemplate(address implementation, bool endorse) public {
    controller.addTemplateCategory(templateCategory);

    controller.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: implementation,
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: false,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );
    if (endorse) controller.toggleTemplateEndorsement(templateCategory, templateId);
  }

  /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  function test__initilization() public {
    assertEq(address(controller.cloneFactory()), address(factory));
    assertEq(address(controller.cloneRegistry()), address(cloneRegistry));
    assertEq(address(controller.templateRegistry()), address(templateRegistry));

    assertEq(controller.owner(), address(this));
    assertEq(factory.owner(), address(controller));
    assertEq(cloneRegistry.owner(), address(controller));
    assertEq(templateRegistry.owner(), address(controller));
  }

  /*//////////////////////////////////////////////////////////////
                        ADD_TEMPLATE_TYPE
    //////////////////////////////////////////////////////////////*/
  function test__addTemplateCategory() public {
    vm.expectEmit(true, true, true, false, address(templateRegistry));
    emit TemplateCategoryAdded(templateCategory);

    controller.addTemplateCategory(templateCategory);

    bytes32[] memory templateCategories = templateRegistry.getTemplateCategories();
    assertEq(templateCategories.length, 1);
    assertEq(templateCategories[0], templateCategory);
    assertTrue(templateRegistry.templateCategoryExists(templateCategory));
  }

  function testFail__addTemplateCategory_nonOwner() public {
    vm.prank(nonOwner);
    controller.addTemplateCategory(templateCategory);
  }

  function testFail__addTemplateCategory_templateCategory_already_exists() public {
    controller.addTemplateCategory(templateCategory);

    vm.expectRevert(TemplateRegistry.TemplateCategoryExists.selector);
    controller.addTemplateCategory(templateCategory);
  }

  function testFail__addTemplateCategory_controller_is_not_dependency_owner() public {
    deployDependencies(address(this));
    nominateDependencyOwner(address(this), address(this));
    deployDeploymentController(address(this));

    controller.addTemplateCategory(templateCategory);
  }

  /*//////////////////////////////////////////////////////////////
                          ADD_TEMPLATE
    //////////////////////////////////////////////////////////////*/

  function test__addTemplate() public {
    controller.addTemplateCategory(templateCategory);
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();

    vm.expectEmit(true, true, true, false, address(templateRegistry));
    emit TemplateAdded(templateCategory, templateId, address(clonableWithInitData));

    controller.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );

    Template memory template = templateRegistry.getTemplate(templateCategory, templateId);
    assertEq(template.implementation, address(clonableWithInitData));
    assertEq(template.metadataCid, metadataCid);
    assertEq(template.requiresInitData, true);
    assertEq(template.registry, address(0x2222));
    assertEq(template.requiredSigs[0], requiredSigs[0]);
    assertEq(template.requiredSigs[7], requiredSigs[7]);

    bytes32[] memory templateIds = templateRegistry.getTemplateIds(templateCategory);
    assertEq(templateIds.length, 1);
    assertEq(templateIds[0], templateId);

    assertTrue(templateRegistry.templateExists(templateId));
  }

  function testFail__addTemplate_templateCategory_doesnt_exists() public {
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();

    controller.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );
  }

  function testFail__addTemplate_template_already_exists() public {
    controller.addTemplateCategory(templateCategory);
    ClonableWithInitData clonableWithInitData = new ClonableWithInitData();

    controller.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );

    controller.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitData),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );
  }

  function testFail__addTemplate_controller_is_not_dependency_owner() public {
    deployDependencies(address(this));
    nominateDependencyOwner(address(this), address(this));
    deployDeploymentController(address(this));

    controller.addTemplateCategory(templateCategory);
    controller.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: address(clonableWithInitDataImpl),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );
  }

  /*//////////////////////////////////////////////////////////////
                    TOGGLE TEMPLATE ENDORSEMENT
    //////////////////////////////////////////////////////////////*/

  function test__toggleTemplateEndorsement() public {
    addTemplate(address(clonableWithoutInitDataImpl), false);

    vm.expectEmit(true, true, true, false, address(templateRegistry));
    emit TemplateEndorsementToggled(templateCategory, templateId, false, true);

    controller.toggleTemplateEndorsement(templateCategory, templateId);

    Template memory template = templateRegistry.getTemplate(templateCategory, templateId);
    assertTrue(template.endorsed);
  }

  function testFail__toggleTemplateEndorsement_templateId_doesnt_exist() public {
    controller.toggleTemplateEndorsement(templateCategory, templateId);
  }

  function testFail__toggleTemplateEndorsement_nonOwner() public {
    addTemplate(address(clonableWithoutInitDataImpl), false);

    vm.prank(nonOwner);
    controller.toggleTemplateEndorsement(templateCategory, templateId);
  }

  /*//////////////////////////////////////////////////////////////
                              DEPLOY
    //////////////////////////////////////////////////////////////*/

  function test__deploy() public {
    addTemplate(address(clonableWithoutInitDataImpl), true);

    vm.expectEmit(true, false, false, false, address(factory));
    emit Deployment(address(0x104fBc016F4bb334D775a19E8A6510109AC63E00));

    address clone = controller.deploy(templateCategory, templateId, "");

    assertEq(ClonableWithoutInitData(clone).val(), 10);
    assertTrue(cloneRegistry.cloneExists(address(clone)));
  }

  function test__deployWithInitData() public {
    controller.addTemplateCategory(templateCategory);
    controller.addTemplate(
      templateCategory,
      "ClonableWithInitData",
      Template({
        implementation: address(clonableWithInitDataImpl),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: address(0x2222),
        requiredSigs: requiredSigs
      })
    );
    controller.toggleTemplateEndorsement(templateCategory, "ClonableWithInitData");

    bytes memory initData = abi.encodeCall(ClonableWithInitData.initialize, (100));

    vm.expectEmit(true, false, false, false, address(factory));
    emit Deployment(address(0x104fBc016F4bb334D775a19E8A6510109AC63E00));

    address clone = controller.deploy(templateCategory, "ClonableWithInitData", initData);

    assertEq(ClonableWithInitData(clone).val(), 100);
    assertTrue(cloneRegistry.cloneExists(address(clone)));
  }

  function testFail__deploy_not_endorsed() public {
    controller.addTemplate(
      templateCategory,
      "ClonableWithInitData",
      Template({
        implementation: address(clonableWithInitDataImpl),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: registry,
        requiredSigs: requiredSigs
      })
    );

    // Call revert method on clone
    bytes memory initData = abi.encodeCall(ClonableWithoutInitData.fail, ());

    controller.deploy(templateCategory, "ClonableWithInitData", initData);
  }

  function testFail__deploy_init() public {
    controller.addTemplate(
      templateCategory,
      "ClonableWithInitData",
      Template({
        implementation: address(clonableWithoutInitDataImpl),
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: true,
        registry: registry,
        requiredSigs: requiredSigs
      })
    );

    // Call revert method on clone
    bytes memory initData = abi.encodeCall(ClonableWithoutInitData.fail, ());

    controller.deploy(templateCategory, "ClonableWithInitData", initData);
  }

  function testFail__deploy_controller_is_not_dependency_owner() public {
    deployDependencies(address(this));
    nominateDependencyOwner(address(this), address(this));
    deployDeploymentController(address(this));
    addTemplate(address(clonableWithoutInitDataImpl), true);

    controller.deploy(templateCategory, templateId, "");
  }

  function testFail__deploy_nonOwner() public {
    addTemplate(address(clonableWithoutInitDataImpl), true);

    vm.prank(nonOwner);
    controller.deploy(templateCategory, templateId, "");
  }

  /*//////////////////////////////////////////////////////////////
                        DEPENDENCY OWNERSHIP
    //////////////////////////////////////////////////////////////*/

  function test__nominateDependencyOwner() public {
    controller.nominateNewDependencyOwner(address(0x2222));
    assertEq(IOwned(address(controller.cloneFactory())).nominatedOwner(), address(0x2222));
    assertEq(IOwned(address(controller.cloneRegistry())).nominatedOwner(), address(0x2222));
    assertEq(IOwned(address(controller.templateRegistry())).nominatedOwner(), address(0x2222));
  }

  function testFail__nominateDependencyOwner_nonOwner() public {
    vm.prank(nonOwner);
    controller.nominateNewDependencyOwner(address(0x2222));
  }

  function test__acceptDependencyOwnership() public {
    deployDependencies(address(this));
    deployDeploymentController(address(this));
    nominateDependencyOwner(address(this), address(controller));

    controller.acceptDependencyOwnership();
    assertEq(IOwned(address(controller.cloneFactory())).owner(), address(controller));
    assertEq(IOwned(address(controller.cloneRegistry())).owner(), address(controller));
    assertEq(IOwned(address(controller.templateRegistry())).owner(), address(controller));
  }
}
