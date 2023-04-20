// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Test } from "forge-std/Test.sol";

import { CloneRegistry } from "../../src/vault/CloneRegistry.sol";
import { CloneFactory } from "../../src/vault/CloneFactory.sol";
import { PermissionRegistry } from "../../src/vault/PermissionRegistry.sol";
import { TemplateRegistry, Template } from "../../src/vault/TemplateRegistry.sol";
import { DeploymentController } from "../../src/vault/DeploymentController.sol";
import { VaultController, IAdapter, VaultInitParams, VaultMetadata } from "../../src/vault/VaultController.sol";
import { Vault } from "../../src/vault/Vault.sol";
import { AdminProxy } from "../../src/vault/AdminProxy.sol";
import { VaultRegistry } from "../../src/vault/VaultRegistry.sol";

import { MultiRewardEscrow } from "../../src/utils/MultiRewardEscrow.sol";
import { MultiRewardStaking } from "../../src/utils/MultiRewardStaking.sol";

import { ICloneRegistry } from "../../src/interfaces/vault/ICloneRegistry.sol";
import { ICloneFactory } from "../../src/interfaces/vault/ICloneFactory.sol";
import { IPermissionRegistry, Permission } from "../../src/interfaces/vault/IPermissionRegistry.sol";
import { ITemplateRegistry } from "../../src/interfaces/vault/ITemplateRegistry.sol";
import { IDeploymentController } from "../../src/interfaces/vault/IDeploymentController.sol";
import { IVaultRegistry } from "../../src/interfaces/vault/IVaultRegistry.sol";
import { IAdminProxy } from "../../src/interfaces/vault/IAdminProxy.sol";
import { IVaultController, DeploymentArgs } from "../../src/interfaces/vault/IVaultController.sol";

import { IMultiRewardEscrow } from "../../src/interfaces/IMultiRewardEscrow.sol";
import { IMultiRewardStaking } from "../../src/interfaces/IMultiRewardStaking.sol";
import { IOwned } from "../../src/interfaces/IOwned.sol";
import { IPausable } from "../../src/interfaces/IPausable.sol";

import { IVault, VaultFees, IERC4626, IERC20 } from "../../src/interfaces/vault/IVault.sol";

import { MockERC20 } from "../utils/mocks/MockERC20.sol";
import { MockAdapter } from "../utils/mocks/MockAdapter.sol";
import { MockStrategy } from "../utils/mocks/MockStrategy.sol";

contract VaultControllerTest is Test {
  ITemplateRegistry templateRegistry;
  IPermissionRegistry permissionRegistry;
  ICloneRegistry cloneRegistry;
  IVaultRegistry vaultRegistry;

  ICloneFactory factory;
  IDeploymentController deploymentController;
  IAdminProxy adminProxy;

  address stakingImpl;
  IMultiRewardStaking staking;
  IMultiRewardEscrow escrow;

  VaultController controller;

  MockERC20 asset;
  IERC20 iAsset;

  MockERC20 rewardToken;
  IERC20 iRewardToken;

  address adapterImpl;

  address strategyImpl;

  address vaultImpl;

  address nonOwner = makeAddr("non owner");
  address registry = makeAddr("registry");

  address alice = address(0xABCD);
  address bob = address(0xDCBA);
  address feeRecipient = address(0x9999);

  bytes32 templateCategory = "templateCategory";
  bytes32 templateId = "MockAdapter";
  string metadataCid = "cid";
  bytes4[8] requiredSigs;
  address[8] swapTokenAddresses;

  event OwnerChanged(address oldOwner, address newOwner);

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

  event VaultAdded(address vault, string metadataCID);

  event NewFeesProposed(VaultFees newFees, uint256 timestamp);
  event ChangedFees(VaultFees oldFees, VaultFees newFees);
  event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);
  event NewAdapterProposed(IERC4626 newAdapter, uint256 timestamp);
  event ChangedAdapter(IERC4626 oldAdapter, IERC4626 newAdapter);
  event QuitPeriodSet(uint256 quitPeriod);
  event Paused(address account);
  event Unpaused(address account);

  event Locked(IERC20 indexed token, address indexed account, uint256 amount, uint32 duration, uint32 offset);
  event RewardsClaimed(IERC20 indexed token, address indexed account, uint256 amount);
  event FeeSet(IERC20 indexed token, uint256 amount);
  event KeeperPercUpdated(uint256 oldPerc, uint256 newPerc);
  event FeeClaimed(IERC20 indexed token, uint256 amount);

  event RewardInfoUpdate(IERC20 rewardsToken, uint160 rewardsPerSecond, uint32 rewardsEndTimestamp);
  event RewardsClaimed(address indexed user, IERC20 rewardsToken, uint256 amount, bool escrowed);

  event VaultDeployed(address indexed vault, address indexed staking, address indexed adapter);
  event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);
  event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);
  event LatestTemplateKeyChanged(bytes32 oldKey, bytes32 newKey);

  event SelectorsVerified();
  event AdapterVerified();
  event StrategySetup();
  event Initialized(uint8 version);

  function setUp() public {
    stakingImpl = address(new MultiRewardStaking());
    adapterImpl = address(new MockAdapter());
    strategyImpl = address(new MockStrategy());
    vaultImpl = address(new Vault());

    asset = new MockERC20("Test Token", "TKN", 18);
    iAsset = IERC20(address(asset));

    rewardToken = new MockERC20("RewardToken", "RTKN", 18);
    iRewardToken = IERC20(address(rewardToken));

    adminProxy = IAdminProxy(address(new AdminProxy(address(this))));

    permissionRegistry = IPermissionRegistry(address(new PermissionRegistry(address(adminProxy))));
    vaultRegistry = IVaultRegistry(address(new VaultRegistry(address(adminProxy))));
    escrow = IMultiRewardEscrow(address(new MultiRewardEscrow(address(adminProxy), feeRecipient)));

    deployDeploymentController();
    deploymentController.nominateNewOwner(address(adminProxy));
    adminProxy.execute(address(deploymentController), abi.encodeWithSelector(IOwned.acceptOwnership.selector, ""));

    controller = new VaultController(
      address(this),
      adminProxy,
      deploymentController,
      vaultRegistry,
      permissionRegistry,
      escrow
    );

    adminProxy.nominateNewOwner(address(controller));
    controller.acceptAdminProxyOwnership();

    bytes32[] memory templateCategories = new bytes32[](4);
    templateCategories[0] = "Vault";
    templateCategories[1] = "Adapter";
    templateCategories[2] = "Strategy";
    templateCategories[3] = "Staking";
    controller.addTemplateCategories(templateCategories);

    addTemplate("Staking", "MultiRewardStaking", stakingImpl, true, true);
  }

  /*//////////////////////////////////////////////////////////////
                              HELPER
    //////////////////////////////////////////////////////////////*/

  function deployDeploymentController() public {
    factory = ICloneFactory(address(new CloneFactory(address(this))));
    cloneRegistry = ICloneRegistry(address(new CloneRegistry(address(this))));
    templateRegistry = ITemplateRegistry(address(new TemplateRegistry(address(this))));

    deploymentController = IDeploymentController(
      address(new DeploymentController(address(this), factory, cloneRegistry, templateRegistry))
    );

    factory.nominateNewOwner(address(deploymentController));
    cloneRegistry.nominateNewOwner(address(deploymentController));
    templateRegistry.nominateNewOwner(address(deploymentController));
    deploymentController.acceptDependencyOwnership();
  }

  function addTemplate(
    bytes32 templateCategory,
    bytes32 templateId,
    address implementation,
    bool requiresInitData,
    bool endorse
  ) public {
    deploymentController.addTemplate(
      templateCategory,
      templateId,
      Template({
        implementation: implementation,
        endorsed: false,
        metadataCid: metadataCid,
        requiresInitData: requiresInitData,
        registry: registry,
        requiredSigs: requiredSigs
      })
    );
    bytes32[] memory templateCategories = new bytes32[](1);
    bytes32[] memory templateIds = new bytes32[](1);
    templateCategories[0] = templateCategory;
    templateIds[0] = templateId;
    if (endorse) controller.toggleTemplateEndorsements(templateCategories, templateIds);
  }

  function deployAdapter() public returns (address) {
    return
      controller.deployAdapter(
        iAsset,
        DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
        DeploymentArgs({ id: "", data: "" }),
        0
      );
  }

  function deployVault() public returns (address) {
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    return
      controller.deployVault(
        VaultInitParams({
          asset: iAsset,
          adapter: IERC4626(address(0)),
          fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
          feeRecipient: feeRecipient,
          depositLimit: type(uint256).max,
          owner: address(this)
        }),
        DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
        DeploymentArgs({ id: "MockStrategy", data: "" }),
        true,
        abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days),
        VaultMetadata({
          vault: address(0),
          staking: address(0),
          creator: address(this),
          metadataCID: metadataCid,
          swapTokenAddresses: swapTokenAddresses,
          swapAddress: address(0x5555),
          exchange: uint256(1)
        }),
        0
      );
  }

  function setPermission(
    address target,
    bool endorsed,
    bool rejected
  ) public {
    address[] memory targets = new address[](1);
    Permission[] memory permissions = new Permission[](1);
    targets[0] = target;
    permissions[0] = Permission(endorsed, rejected);
    controller.setPermissions(targets, permissions);
  }

  /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  function test__initilization() public {
    assertEq(address(controller.deploymentController()), address(deploymentController));
    assertEq(address(controller.permissionRegistry()), address(permissionRegistry));
    assertEq(address(controller.vaultRegistry()), address(vaultRegistry));
    assertEq(address(controller.adminProxy()), address(adminProxy));
    assertEq(address(controller.escrow()), address(escrow));

    assertEq(controller.activeTemplateId("Staking"), "MultiRewardStaking");
    assertEq(controller.activeTemplateId("Vault"), "V1");

    assertEq(controller.owner(), address(this));
  }

  /*//////////////////////////////////////////////////////////////
                        VAULT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

  function test__deployVault() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    swapTokenAddresses[0] = address(0x9999);
    address adapterClone = 0xD6C5fA22BBE89db86245e111044a880213b35705;
    address strategyClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
    address stakingClone = 0xE64C695617819cE724c1d35a37BCcFbF5586F752;

    uint256 callTimestamp = block.timestamp;
    address vaultClone = controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(0)),
        fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "MockStrategy", data: "" }),
      true,
      abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days),
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      0
    );
    // Assert Vault
    assertTrue(cloneRegistry.cloneExists(vaultClone));
    assertEq(IVault(vaultClone).asset(), address(iAsset));
    assertEq(IVault(vaultClone).adapter(), adapterClone);
    assertEq(IVault(vaultClone).fees().deposit, 100);
    assertEq(IVault(vaultClone).fees().withdrawal, 200);
    assertEq(IVault(vaultClone).fees().management, 300);
    assertEq(IVault(vaultClone).fees().performance, 400);
    assertEq(IVault(vaultClone).feeRecipient(), feeRecipient);
    assertEq(IOwned(vaultClone).owner(), address(adminProxy));
    assertEq(IVault(vaultClone).depositLimit(), type(uint256).max);
    // Assert Vault Metadata
    assertEq(vaultRegistry.getVault(vaultClone).vault, vaultClone);
    assertEq(vaultRegistry.getVault(vaultClone).staking, stakingClone);
    assertEq(vaultRegistry.getVault(vaultClone).creator, address(this));
    assertEq(vaultRegistry.getVault(vaultClone).metadataCID, metadataCid);
    assertEq(vaultRegistry.getVault(vaultClone).swapTokenAddresses[0], address(0x9999));
    assertEq(vaultRegistry.getVault(vaultClone).swapAddress, address(0x5555));
    assertEq(vaultRegistry.getVault(vaultClone).exchange, uint256(1));
    // Assert Adapter
    assertTrue(cloneRegistry.cloneExists(adapterClone));
    assertEq(MockAdapter(adapterClone).initValue(), 100);
    assertEq(IAdapter(adapterClone).harvestCooldown(), 1 days);
    assertEq(IAdapter(adapterClone).performanceFee(), 1000);
    assertEq(IAdapter(adapterClone).strategy(), strategyClone);
    // Assert Strategy
    assertTrue(cloneRegistry.cloneExists(strategyClone));
    // Assert Staking
    assertTrue(cloneRegistry.cloneExists(stakingClone));
    assertEq(IERC4626(stakingClone).asset(), vaultClone);

    assertEq(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).ONE, 1 ether);
    assertEq(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).rewardsPerSecond, 0.1 ether);
    assertEq(
      uint256(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).rewardsEndTimestamp),
      callTimestamp + 10
    );
    assertEq(uint256(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).index), 1 ether);
    assertEq(uint256(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).lastUpdatedTimestamp), callTimestamp);

    assertEq(uint256(IMultiRewardStaking(stakingClone).escrowInfos(iRewardToken).escrowPercentage), 10000000);
    assertEq(uint256(IMultiRewardStaking(stakingClone).escrowInfos(iRewardToken).escrowDuration), 2 days);
    assertEq(uint256(IMultiRewardStaking(stakingClone).escrowInfos(iRewardToken).offset), 1 days);
  }

  function test__deployVault_without_strategy() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    swapTokenAddresses[0] = address(0x9999);
    address adapterClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
    address stakingClone = 0x949DEa045FE979a11F0D4A929446F83072D81095;

    uint256 callTimestamp = block.timestamp;
    address vaultClone = controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(0)),
        fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      true,
      abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days),
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      0
    );
    // Check for empty strategy
    assertEq(IAdapter(adapterClone).strategy(), address(0));
  }

  function test__deployVault_without_rewards() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    swapTokenAddresses[0] = address(0x9999);
    address adapterClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
    address stakingClone = 0x949DEa045FE979a11F0D4A929446F83072D81095;

    uint256 callTimestamp = block.timestamp;
    address vaultClone = controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(0)),
        fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      true,
      "",
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      0
    );
    // Check for empty reward info
    assertEq(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).ONE, 0);
    assertEq(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).rewardsPerSecond, 0);
    assertEq(uint256(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).rewardsEndTimestamp), 0);
    assertEq(uint256(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).index), 0);
    assertEq(uint256(IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).lastUpdatedTimestamp), 0);
    // Check for empty escrow info
    assertEq(uint256(IMultiRewardStaking(stakingClone).escrowInfos(iRewardToken).escrowPercentage), 0);
    assertEq(uint256(IMultiRewardStaking(stakingClone).escrowInfos(iRewardToken).escrowDuration), 0);
    assertEq(uint256(IMultiRewardStaking(stakingClone).escrowInfos(iRewardToken).offset), 0);
  }

  function test__deployVault_adapter_given() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    swapTokenAddresses[0] = address(0x9999);
    address stakingClone = 0x949DEa045FE979a11F0D4A929446F83072D81095;

    address adapterClone = controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(300)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );

    uint256 callTimestamp = block.timestamp;
    address vaultClone = controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(adapterClone)),
        fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: "", data: "" }),
      DeploymentArgs({ id: "", data: "" }),
      true,
      abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days),
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      0
    );
    // Assert Vault
    assertEq(IVault(vaultClone).adapter(), adapterClone);
    // Assert Adapter
    assertTrue(cloneRegistry.cloneExists(adapterClone));
    assertEq(MockAdapter(adapterClone).initValue(), 300);
    assertEq(IAdapter(adapterClone).harvestCooldown(), 1 days);
    assertEq(IAdapter(adapterClone).performanceFee(), 1000);
    assertEq(IAdapter(adapterClone).strategy(), address(0));
  }

  function test__deployVault_with_initial_deposit() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    asset.mint(address(this), 1 ether);
    asset.approve(address(controller), 1 ether);

    swapTokenAddresses[0] = address(0x9999);
    address adapterClone = 0xD6C5fA22BBE89db86245e111044a880213b35705;
    address strategyClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
    address stakingClone = 0xE64C695617819cE724c1d35a37BCcFbF5586F752;

    uint256 callTimestamp = block.timestamp;
    address vaultClone = controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(0)),
        fees: VaultFees({ deposit: 0, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "MockStrategy", data: "" }),
      true,
      abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days),
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      1 ether
    );
    // Check the initial deposit
    assertEq(IERC20(adapterClone).balanceOf(vaultClone), 1 ether * 1e9);
    assertEq(IERC4626(adapterClone).totalAssets(), 1 ether);
    assertEq(IERC4626(adapterClone).totalSupply(), 1 ether * 1e9);
    assertEq(IERC20(vaultClone).balanceOf(address(this)), 1 ether * 1e9);
    assertEq(IERC4626(vaultClone).totalAssets(), 1 ether);
    assertEq(IERC4626(vaultClone).totalSupply(), 1 ether * 1e9);
  }

  function testFail__deployVault_creator_rejected() public {
    setPermission(address(bob), false, true);
    deployVault();
  }

  function testFail__deployVault_creator_not_endorsed() public {
    setPermission(address(1), true, false);
    setPermission(address(bob), false, false);
    deployVault();
  }

  function testFail__deployVault_without_staking_but_with_rewards() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    rewardToken.mint(address(this), 10 ether);
    rewardToken.approve(address(controller), 10 ether);

    controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(0)),
        fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "MockStrategy", data: "" }),
      false,
      abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days),
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      0
    );
  }

  function testFail__deployVault_without_adapter_nor_adapterData() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);

    controller.deployVault(
      VaultInitParams({
        asset: iAsset,
        adapter: IERC4626(address(0)),
        fees: VaultFees({ deposit: 100, withdrawal: 200, management: 300, performance: 400 }),
        feeRecipient: feeRecipient,
        depositLimit: type(uint256).max,
        owner: address(this)
      }),
      DeploymentArgs({ id: "", data: "" }),
      DeploymentArgs({ id: "", data: "" }),
      false,
      "",
      VaultMetadata({
        vault: address(0),
        staking: address(0),
        creator: address(this),
        metadataCID: metadataCid,
        swapTokenAddresses: swapTokenAddresses,
        swapAddress: address(0x5555),
        exchange: uint256(1)
      }),
      0
    );
  }

  /*//////////////////////////////////////////////////////////////
                        ADAPTER DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

  function test__deployAdapter() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    address adapterClone = 0xD6C5fA22BBE89db86245e111044a880213b35705;
    address strategyClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;

    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "MockStrategy", data: "" }),
      0
    );

    assertEq(MockAdapter(adapterClone).initValue(), 100);
    assertEq(IAdapter(adapterClone).harvestCooldown(), 1 days);
    assertEq(IAdapter(adapterClone).performanceFee(), 1000);
    assertEq(IAdapter(adapterClone).strategy(), strategyClone);
    assertTrue(cloneRegistry.cloneExists(adapterClone));
    assertTrue(cloneRegistry.cloneExists(strategyClone));
  }

  function test__deployAdapter_without_strategy() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    address adapterClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;

    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );

    assertEq(MockAdapter(adapterClone).initValue(), 100);
    assertEq(IAdapter(adapterClone).harvestCooldown(), 1 days);
    assertEq(IAdapter(adapterClone).performanceFee(), 1000);
    assertEq(IAdapter(adapterClone).strategy(), address(0));
    assertTrue(cloneRegistry.cloneExists(adapterClone));
  }

  function test__deployAdapter_with_initial_deposit() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    controller.setPerformanceFee(uint256(1000));
    controller.setHarvestCooldown(1 days);
    asset.mint(address(this), 1 ether);
    asset.approve(address(controller), 1 ether);

    address adapterClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;

    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      1 ether
    );

    // Check the initial deposit
    assertEq(IERC20(adapterClone).balanceOf(address(this)), 1 ether * 1e9);
    assertEq(IERC4626(adapterClone).totalAssets(), 1 ether);
    assertEq(IERC4626(adapterClone).totalSupply(), 1 ether * 1e9);
  }

  function testFail__deployAdapter_token_rejected() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    setPermission(address(iAsset), false, true);

    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
  }

  function testFail__deployAdapter_token_not_endorsed() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    setPermission(address(0), true, false);
    setPermission(address(iAsset), false, true);

    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
  }

  function testFail__deployAdapter_token_is_addressZero() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);

    controller.deployAdapter(
      IERC20(address(0)),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
  }

  function testFail__deployAdapter_token_is_clone() public {
    addTemplate("Adapter", templateId, adapterImpl, true, true);

    address adapterClone = controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );

    controller.deployAdapter(
      IERC20(adapterClone),
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
  }

  function testFail__deployAdapter_creator_rejected() public {
    setPermission(address(bob), false, true);

    vm.prank(bob);
    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
  }

  function testFail__deployAdapter_creator_not_endorsed() public {
    setPermission(address(1), true, false);
    setPermission(address(bob), false, false);

    vm.prank(bob);
    controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
  }

  /*//////////////////////////////////////////////////////////////
                        STAKING DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

  function test__deployStaking() public {
    address stakingClone = controller.deployStaking(iAsset);

    assertTrue(cloneRegistry.cloneExists(stakingClone));
    assertEq(IERC4626(stakingClone).asset(), address(iAsset));
  }

  function testFail__deployStaking_token_rejected() public {
    setPermission(address(iAsset), false, true);

    controller.deployStaking(iAsset);
  }

  function testFail__deployStaking_token_not_endorsed() public {
    setPermission(address(0), true, false);
    setPermission(address(iAsset), false, true);

    controller.deployStaking(iAsset);
  }

  function testFail__deployStaking_token_is_addressZero() public {
    controller.deployStaking(IERC20(address(0)));
  }

  function testFail__deployStaking_token_is_clone() public {
    address stakingClone = controller.deployStaking(iAsset);

    controller.deployStaking(IERC20(stakingClone));
  }

  function testFail__deployStaking_creator_rejected() public {
    setPermission(address(bob), false, true);

    vm.prank(bob);
    controller.deployStaking(iAsset);
  }

  function testFail__deployStaking_creator_not_endorsed() public {
    setPermission(address(1), true, false);
    setPermission(address(bob), false, false);

    vm.prank(bob);
    controller.deployStaking(iAsset);
  }

  /*//////////////////////////////////////////////////////////////
                      PROPOSE VAULT ADAPTER
    //////////////////////////////////////////////////////////////*/

  function test__proposeVaultAdapters() public {
    address[] memory targets = new address[](1);
    IERC4626[] memory adapters = new IERC4626[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);

    address vault = deployVault();
    targets[0] = vault;

    address adapter = controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
    adapters[0] = IERC4626(adapter);

    uint256 callTime = block.timestamp;
    controller.proposeVaultAdapters(targets, adapters);

    assertEq(IVault(vault).proposedAdapter(), adapter);
    assertEq(IVault(vault).proposedAdapterTime(), callTime);
  }

  function testFail__proposeVaultAdapters_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    IERC4626[] memory adapters = new IERC4626[](1);

    controller.proposeVaultAdapters(targets, adapters);
  }

  function testFail__proposeVaultAdapters_adapter_doesnt_exist() public {
    address[] memory targets = new address[](1);
    IERC4626[] memory adapters = new IERC4626[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);

    address vault = deployVault();
    targets[0] = vault;

    controller.proposeVaultAdapters(targets, adapters);
  }

  function testFail__proposeVaultAdapters_nonCreator() public {
    address[] memory targets = new address[](1);
    IERC4626[] memory adapters = new IERC4626[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);

    address vault = deployVault();
    targets[0] = vault;

    vm.prank(bob);
    controller.proposeVaultAdapters(targets, adapters);
  }

  /*//////////////////////////////////////////////////////////////
                      CHANGE VAULT ADAPTER
    //////////////////////////////////////////////////////////////*/

  function test__changeVaultAdapters() public {
    address[] memory targets = new address[](1);
    IERC4626[] memory adapters = new IERC4626[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);

    address vault = deployVault();
    targets[0] = vault;

    address adapter = controller.deployAdapter(
      iAsset,
      DeploymentArgs({ id: templateId, data: abi.encode(uint256(100)) }),
      DeploymentArgs({ id: "", data: "" }),
      0
    );
    adapters[0] = IERC4626(adapter);

    controller.proposeVaultAdapters(targets, adapters);

    vm.warp(block.timestamp + 3 days + 1);
    controller.changeVaultAdapters(targets);

    assertEq(IVault(vault).adapter(), adapter);
  }

  /*//////////////////////////////////////////////////////////////
                      PROPOSE VAULT FEES
    //////////////////////////////////////////////////////////////*/

  function test__proposeVaultFees() public {
    address[] memory targets = new address[](1);
    VaultFees[] memory fees = new VaultFees[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    fees[0] = VaultFees({ deposit: 10, withdrawal: 20, management: 30, performance: 40 });

    uint256 callTime = block.timestamp;
    controller.proposeVaultFees(targets, fees);

    assertEq(IVault(vault).proposedFees().deposit, 10);
    assertEq(IVault(vault).proposedFees().withdrawal, 20);
    assertEq(IVault(vault).proposedFees().management, 30);
    assertEq(IVault(vault).proposedFees().performance, 40);
    assertEq(IVault(vault).proposedFeeTime(), callTime);
  }

  function testFail__proposeVaultFees_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    VaultFees[] memory fees = new VaultFees[](1);

    controller.proposeVaultFees(targets, fees);
  }

  function testFail__proposeVaultFees_nonCreator() public {
    address[] memory targets = new address[](1);
    VaultFees[] memory fees = new VaultFees[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;

    vm.prank(bob);
    controller.proposeVaultFees(targets, fees);
  }

  /*//////////////////////////////////////////////////////////////
                      CHANGE VAULT FEES
    //////////////////////////////////////////////////////////////*/

  function test__changeVaultFees() public {
    address[] memory targets = new address[](1);
    VaultFees[] memory fees = new VaultFees[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    fees[0] = VaultFees({ deposit: 10, withdrawal: 20, management: 30, performance: 40 });

    controller.proposeVaultFees(targets, fees);

    vm.warp(block.timestamp + 3 days + 1);
    controller.changeVaultFees(targets);

    assertEq(IVault(vault).fees().deposit, 10);
    assertEq(IVault(vault).fees().withdrawal, 20);
    assertEq(IVault(vault).fees().management, 30);
    assertEq(IVault(vault).fees().performance, 40);
  }

  /*//////////////////////////////////////////////////////////////
                      SET VAULT QUIT PERIOD
    //////////////////////////////////////////////////////////////*/

  function test__setVaultQuitPeriods() public {
    address[] memory targets = new address[](1);
    uint256[] memory quitPeriods = new uint256[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    quitPeriods[0] = 1 days;

    // Pass the inital quit period
    vm.warp(block.timestamp + 3 days);
    controller.setVaultQuitPeriods(targets, quitPeriods);

    assertEq(IVault(vault).quitPeriod(), 1 days);
  }

  function testFail__setVaultQuitPeriods_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    uint256[] memory quitPeriods = new uint256[](1);

    controller.setVaultQuitPeriods(targets, quitPeriods);
  }

  function testFail__setVaultQuitPeriods_nonCreator() public {
    address[] memory targets = new address[](1);
    uint256[] memory quitPeriods = new uint256[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    quitPeriods[0] = 1 days;

    vm.prank(bob);
    controller.setVaultQuitPeriods(targets, quitPeriods);
  }

  /*//////////////////////////////////////////////////////////////
                      SET VAULT QUIT PERIOD
    //////////////////////////////////////////////////////////////*/

  function test__setVaultFeeRecipients() public {
    address[] memory targets = new address[](1);
    address[] memory feeRecipients = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    feeRecipients[0] = address(0x44444);

    // Pass the inital quit period
    vm.warp(block.timestamp + 3 days);
    controller.setVaultFeeRecipients(targets, feeRecipients);

    assertEq(IVault(vault).feeRecipient(), address(0x44444));
  }

  function testFail__setVaultFeeRecipients_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    address[] memory feeRecipients = new address[](1);

    controller.setVaultFeeRecipients(targets, feeRecipients);
  }

  function testFail__setVaultFeeRecipients_nonCreator() public {
    address[] memory targets = new address[](1);
    address[] memory feeRecipients = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    feeRecipients[0] = address(0x44444);

    vm.prank(bob);
    controller.setVaultFeeRecipients(targets, feeRecipients);
  }

  /*//////////////////////////////////////////////////////////////
                      SET VAULT DEPOSIT LIMIT
    //////////////////////////////////////////////////////////////*/

  function test__setVaultDepositLimits() public {
    address[] memory targets = new address[](1);
    uint256[] memory depositLimits = new uint256[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    depositLimits[0] = uint256(10);

    controller.setVaultDepositLimits(targets, depositLimits);

    assertEq(IVault(vault).depositLimit(), uint256(10));
  }

  function testFail__setVaultDepositLimits_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    uint256[] memory depositLimits = new uint256[](1);

    controller.setVaultDepositLimits(targets, depositLimits);
  }

  function testFail__setVaultDepositLimits_nonCreator() public {
    address[] memory targets = new address[](1);
    uint256[] memory depositLimits = new uint256[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    depositLimits[0] = uint256(10);

    vm.prank(bob);
    controller.setVaultDepositLimits(targets, depositLimits);
  }

  /*//////////////////////////////////////////////////////////////
                      SET PERMISSIONS
    //////////////////////////////////////////////////////////////*/

  function test__setPermissions() public {
    address[] memory targets = new address[](1);
    targets[0] = address(0x1);
    Permission[] memory permissions = new Permission[](1);
    permissions[0] = Permission(true, false);

    controller.setPermissions(targets, permissions);
    assertTrue(permissionRegistry.endorsed(address(0x1)));
    assertFalse(permissionRegistry.rejected(address(0x1)));
  }

  function testFail__setPermissions_nonOwner() public {
    address[] memory targets = new address[](1);
    targets[0] = address(0x1);
    Permission[] memory permissions = new Permission[](1);
    permissions[0] = Permission(true, false);

    vm.prank(nonOwner);
    controller.setPermissions(targets, permissions);
  }

  /*//////////////////////////////////////////////////////////////
                    ADD STAKING REWARD TOKEN
    //////////////////////////////////////////////////////////////*/

  function test__addStakingRewardsTokens() public {
    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    address staking = vaultRegistry.getVault(vault).staking;

    MockERC20 rewardToken2 = new MockERC20("Reward Token2", "RTKN2", 18);
    IERC20 iRewardToken2 = IERC20(address(rewardToken2));
    rewardToken2.mint(address(this), 10 ether);
    rewardToken2.approve(address(controller), 10 ether);

    targets[0] = vault;
    rewardsData[0] = abi.encode(address(rewardToken2), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    uint256 callTimestamp = block.timestamp;
    controller.addStakingRewardsTokens(targets, rewardsData);

    // RewardsInfo
    assertEq(IMultiRewardStaking(staking).rewardInfos(iRewardToken2).ONE, 1 ether);
    assertEq(IMultiRewardStaking(staking).rewardInfos(iRewardToken2).rewardsPerSecond, 0.1 ether);
    assertEq(uint256(IMultiRewardStaking(staking).rewardInfos(iRewardToken2).rewardsEndTimestamp), callTimestamp + 10);
    assertEq(uint256(IMultiRewardStaking(staking).rewardInfos(iRewardToken2).index), 1 ether);
    assertEq(uint256(IMultiRewardStaking(staking).rewardInfos(iRewardToken2).lastUpdatedTimestamp), callTimestamp);
    // EscrowInfo
    assertEq(uint256(IMultiRewardStaking(staking).escrowInfos(iRewardToken2).escrowPercentage), 10000000);
    assertEq(uint256(IMultiRewardStaking(staking).escrowInfos(iRewardToken2).escrowDuration), 2 days);
    assertEq(uint256(IMultiRewardStaking(staking).escrowInfos(iRewardToken2).offset), 1 days);
  }

  function testFail__addStakingRewardsTokens_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    bytes[] memory rewardsData = new bytes[](1);

    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  function testFail__addStakingRewardsTokens_token_rejected() public {
    setPermission(address(iAsset), false, false);
    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    rewardsData[0] = abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  function testFail__addStakingRewardsTokens_token_not_endorsed() public {
    setPermission(address(0), true, false);
    setPermission(address(rewardToken), false, true);

    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    rewardsData[0] = abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  function testFail__addStakingRewardsTokens_token_is_addressZero() public {
    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    rewardsData[0] = abi.encode(address(0), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  function testFail__addStakingRewardsTokens_token_is_clone() public {
    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();

    rewardsData[0] = abi.encode(vault, 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  function testFail__addStakingRewardsTokens_nonCreator() public {
    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();

    targets[0] = vault;
    rewardsData[0] = abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    vm.prank(bob);
    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  function testFail__addStakingRewardsTokens_nonOwner() public {
    address[] memory targets = new address[](1);
    bytes[] memory rewardsData = new bytes[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();

    targets[0] = vault;
    rewardsData[0] = abi.encode(address(rewardToken), 0.1 ether, 1 ether, true, 10000000, 2 days, 1 days);

    vm.prank(nonOwner);
    controller.addStakingRewardsTokens(targets, rewardsData);
  }

  /*//////////////////////////////////////////////////////////////
                    CHANGE STAKING REWARDS SPEED
    //////////////////////////////////////////////////////////////*/

  function test__changeStakingRewardsSpeeds() public {
    address[] memory targets = new address[](1);
    IERC20[] memory rewardTokens = new IERC20[](1);
    uint160[] memory rewardSpeeds = new uint160[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    address staking = vaultRegistry.getVault(vault).staking;

    targets[0] = vault;
    rewardTokens[0] = iRewardToken;
    rewardSpeeds[0] = 0.2 ether;

    controller.changeStakingRewardsSpeeds(targets, rewardTokens, rewardSpeeds);
    assertEq(IMultiRewardStaking(staking).rewardInfos(iRewardToken).rewardsPerSecond, 0.2 ether);
  }

  function testFail__changeStakingRewardsSpeeds_mismatching_arrays() public {
    address[] memory targets = new address[](1);
    IERC20[] memory rewardTokens = new IERC20[](2);
    uint160[] memory rewardSpeeds = new uint160[](2);

    controller.changeStakingRewardsSpeeds(targets, rewardTokens, rewardSpeeds);
  }

  function testFail__changeStakingRewardsSpeeds_nonCreator() public {
    address[] memory targets = new address[](1);
    IERC20[] memory rewardTokens = new IERC20[](1);
    uint160[] memory rewardSpeeds = new uint160[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    address staking = vaultRegistry.getVault(vault).staking;

    targets[0] = vault;
    rewardTokens[0] = iRewardToken;
    rewardSpeeds[0] = 0.2 ether;

    vm.prank(bob);
    controller.changeStakingRewardsSpeeds(targets, rewardTokens, rewardSpeeds);
  }

  /*//////////////////////////////////////////////////////////////
                      FUND STAKING REWARD
    //////////////////////////////////////////////////////////////*/

  function test__fundStakingRewards() public {
    address[] memory targets = new address[](1);
    IERC20[] memory rewardTokens = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);

    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    rewardToken.mint(address(this), 10 ether);
    uint256 callTimestamp = block.timestamp;
    address vault = deployVault();
    address staking = vaultRegistry.getVault(vault).staking;

    targets[0] = vault;
    rewardTokens[0] = iRewardToken;
    amounts[0] = 10 ether;

    rewardToken.approve(address(controller), 10 ether);
    controller.fundStakingRewards(targets, rewardTokens, amounts);

    assertEq(rewardToken.balanceOf(staking), 11 ether);
    assertEq(uint256(IMultiRewardStaking(staking).rewardInfos(iRewardToken).rewardsEndTimestamp), callTimestamp + 110);
  }

  function testFail__fundStakingRewards_mismatching_arrays() public {
    address[] memory targets = new address[](2);
    IERC20[] memory rewardTokens = new IERC20[](1);
    uint256[] memory amounts = new uint256[](1);

    controller.fundStakingRewards(targets, rewardTokens, amounts);
  }

  /*//////////////////////////////////////////////////////////////
                      SET ESCROW TOKEN FEE
    //////////////////////////////////////////////////////////////*/

  function test__setEscrowTokenFees() public {
    IERC20[] memory targets = new IERC20[](1);
    uint256[] memory fees = new uint256[](1);
    targets[0] = iRewardToken;
    fees[0] = 1e14;

    controller.setEscrowTokenFees(targets, fees);
    assertEq(escrow.fees(iRewardToken).feePerc, 1e14);
  }

  function testFail__setEscrowTokenFees_mismatching_arrays() public {
    IERC20[] memory targets = new IERC20[](2);
    uint256[] memory fees = new uint256[](1);

    controller.setEscrowTokenFees(targets, fees);
  }

  function testFail__setEscrowTokenFees_nonOwner() public {
    IERC20[] memory targets = new IERC20[](1);
    uint256[] memory fees = new uint256[](1);

    vm.prank(nonOwner);
    controller.setEscrowTokenFees(targets, fees);
  }

  /*//////////////////////////////////////////////////////////////
                        ADD TEMPLATE TYPE
    //////////////////////////////////////////////////////////////*/
  function test__addTemplateCategories() public {
    vm.expectEmit(true, true, true, false, address(templateRegistry));
    emit TemplateCategoryAdded(templateCategory);

    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;
    controller.addTemplateCategories(templateCategories);

    templateCategories = templateRegistry.getTemplateCategories();
    assertEq(templateCategories.length, 5);
    assertEq(templateCategories[4], templateCategory);
    assertTrue(templateRegistry.templateCategoryExists(templateCategory));
  }

  function testFail__addTemplateCategories_templateCategory_already_exists() public {
    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;

    controller.addTemplateCategories(templateCategories);

    vm.expectRevert(TemplateRegistry.TemplateCategoryExists.selector);
    controller.addTemplateCategories(templateCategories);
  }

  function testFail__addTemplateCategories_nonOwner() public {
    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;

    vm.prank(nonOwner);
    controller.addTemplateCategories(templateCategories);
  }

  /*//////////////////////////////////////////////////////////////
                    TOGGLE TEMPLATE ENDORSEMENT
    //////////////////////////////////////////////////////////////*/

  function test__toggleTemplateEndorsements() public {
    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;
    bytes32[] memory templateIds = new bytes32[](1);
    templateIds[0] = templateId;

    controller.addTemplateCategories(templateCategories);
    addTemplate(templateCategory, templateId, address(adapterImpl), true, false);

    vm.expectEmit(true, true, true, false, address(templateRegistry));
    emit TemplateEndorsementToggled(templateCategory, templateId, false, true);

    controller.toggleTemplateEndorsements(templateCategories, templateIds);

    Template memory template = templateRegistry.getTemplate(templateCategory, templateId);
    assertTrue(template.endorsed);
  }

  function testFail__toggleTemplateEndorsements_mismatching_arrays() public {
    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;
    bytes32[] memory templateIds = new bytes32[](1);
    templateIds[0] = templateId;

    controller.addTemplateCategories(templateCategories);
    addTemplate(templateCategory, templateId, address(adapterImpl), true, false);

    bytes32[] memory templateCategories2 = new bytes32[](2);
    controller.toggleTemplateEndorsements(templateCategories2, templateIds);
  }

  function testFail__toggleTemplateEndorsements_templateId_doesnt_exist() public {
    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;
    bytes32[] memory templateIds = new bytes32[](1);
    templateIds[0] = templateId;
    controller.addTemplateCategories(templateCategories);

    controller.toggleTemplateEndorsements(templateCategories, templateIds);
  }

  function testFail__toggleTemplateEndorsements_nonOwner() public {
    bytes32[] memory templateCategories = new bytes32[](1);
    templateCategories[0] = templateCategory;
    bytes32[] memory templateIds = new bytes32[](1);
    templateIds[0] = templateId;

    vm.prank(nonOwner);
    controller.toggleTemplateEndorsements(templateCategories, templateIds);
  }

  /*//////////////////////////////////////////////////////////////
                      PAUSE / UNPAUSE ADAPTER
    //////////////////////////////////////////////////////////////*/

  function test__pauseAdapters() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;

    controller.pauseAdapters(targets);
    assertTrue(IPausable(IVault(vault).adapter()).paused());
  }

  function testFail__pauseAdapters_nonOwner() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;

    vm.prank(nonOwner);
    controller.pauseAdapters(targets);
  }

  function test__unpauseAdapters() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    controller.pauseAdapters(targets);

    controller.unpauseAdapters(targets);
    assertFalse(IPausable(IVault(vault).adapter()).paused());
  }

  function testFail__unpauseAdapters_nonOwner() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    controller.pauseAdapters(targets);

    vm.prank(nonOwner);
    controller.unpauseAdapters(targets);
  }

  /*//////////////////////////////////////////////////////////////
                      PAUSE / UNPAUSE VAULT
    //////////////////////////////////////////////////////////////*/

  function test__pauseVaults() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;

    controller.pauseVaults(targets);
    assertTrue(IPausable(vault).paused());
  }

  function testFail__pauseVaults_nonCreator() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;

    vm.prank(bob);
    controller.pauseVaults(targets);
  }

  function test__unpauseVaults() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    controller.pauseVaults(targets);

    controller.unpauseVaults(targets);
    assertFalse(IPausable(vault).paused());
  }

  function testFail__unpauseVaults_nonCreator() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
    addTemplate("Vault", "V1", vaultImpl, true, true);
    address vault = deployVault();
    targets[0] = vault;
    controller.pauseVaults(targets);

    vm.prank(bob);
    controller.unpauseVaults(targets);
  }

  /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TRANSFER
    //////////////////////////////////////////////////////////////*/

  function test__nominateNewAdminProxyOwner() public {
    controller.nominateNewAdminProxyOwner(bob);
    assertEq(adminProxy.nominatedOwner(), bob);
  }

  function testFail__nominateNewAdminProxyOwner_nonOwner() public {
    vm.prank(nonOwner);
    controller.nominateNewAdminProxyOwner(bob);
  }

  function test__acceptAdminProxyOwnership() public {
    VaultController newController = new VaultController(
      address(this),
      adminProxy,
      deploymentController,
      vaultRegistry,
      permissionRegistry,
      escrow
    );
    controller.nominateNewAdminProxyOwner(address(newController));

    newController.acceptAdminProxyOwnership();
    assertEq(adminProxy.owner(), address(newController));
  }

  function testFail__acceptAdminProxyOwnership_nonOwner() public {
    controller.nominateNewAdminProxyOwner(bob);

    vm.prank(nonOwner);
    controller.acceptAdminProxyOwnership();
  }

  /*//////////////////////////////////////////////////////////////
                        SET MANAGEMENT FEE
    //////////////////////////////////////////////////////////////*/

  function test__setPerformanceFee() public {
    controller.setPerformanceFee(1e16);
    assertEq(controller.performanceFee(), 1e16);
  }

  function testFail__setPerformanceFee_fee_out_of_bonds() public {
    controller.setPerformanceFee(3e17);
  }

  function testFail__setPerformanceFee_nonOwner() public {
    vm.prank(nonOwner);
    controller.setPerformanceFee(1e16);
  }

  function test__setAdapterPerformanceFees() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    address adapter = deployAdapter();
    targets[0] = adapter;
    controller.setPerformanceFee(1e16);

    controller.setAdapterPerformanceFees(targets);
    assertEq(IAdapter(adapter).performanceFee(), 1e16);
  }

  function testFail__setAdapterPerformanceFees_nonOwner() public {
    address[] memory targets = new address[](1);

    vm.prank(nonOwner);
    controller.setAdapterPerformanceFees(targets);
  }

  /*//////////////////////////////////////////////////////////////
                    SET ADAPTER HARVEST COOLDOWN
    //////////////////////////////////////////////////////////////*/

  function test__setHarvestCooldown() public {
    controller.setHarvestCooldown(1 hours);
    assertEq(controller.harvestCooldown(), 1 hours);
  }

  function testFail__setHarvestCooldown_fee_out_of_bonds() public {
    controller.setHarvestCooldown(2 days);
  }

  function testFail__setHarvestCooldown_nonOwner() public {
    vm.prank(nonOwner);
    controller.setHarvestCooldown(1 hours);
  }

  function test__setAdapterHarvestCooldowns() public {
    address[] memory targets = new address[](1);
    addTemplate("Adapter", templateId, adapterImpl, true, true);
    address adapter = deployAdapter();
    targets[0] = adapter;
    controller.setHarvestCooldown(1 hours);

    controller.setAdapterHarvestCooldowns(targets);
    assertEq(IAdapter(adapter).harvestCooldown(), 1 hours);
  }

  function testFail__setAdapterHarvestCooldowns_nonOwner() public {
    address[] memory targets = new address[](1);

    vm.prank(nonOwner);
    controller.setAdapterHarvestCooldowns(targets);
  }

  /*//////////////////////////////////////////////////////////////
                    SET DEPLOYMENT CONTROLLER
    //////////////////////////////////////////////////////////////*/

  function test__setDeploymentController() public {
    IDeploymentController newDeploymentController = IDeploymentController(
      address(new DeploymentController(address(adminProxy), factory, cloneRegistry, templateRegistry))
    );

    controller.setDeploymentController(newDeploymentController);

    assertEq(address(controller.deploymentController()), address(newDeploymentController));
    assertEq(address(controller.cloneRegistry()), address(cloneRegistry));
    assertEq(address(controller.templateRegistry()), address(templateRegistry));
    assertEq(factory.owner(), address(newDeploymentController));
    assertEq(cloneRegistry.owner(), address(newDeploymentController));
    assertEq(templateRegistry.owner(), address(newDeploymentController));
  }

  function testFail__setDeploymentController_addressZero() public {
    controller.setDeploymentController(IDeploymentController(address(0)));
  }

  function testFail__setDeploymentController_old_address() public {
    controller.setDeploymentController(IDeploymentController(address(deploymentController)));
  }

  function testFail__setDeploymentController_nonOwner() public {
    IDeploymentController newDeploymentController = IDeploymentController(
      address(
        new DeploymentController(address(this), factory, ICloneRegistry(address(1)), ITemplateRegistry(address(2)))
      )
    );
    vm.prank(nonOwner);
    controller.setDeploymentController(newDeploymentController);
  }

  /*//////////////////////////////////////////////////////////////
                    SET LATEST TEMPLATE KEY
    //////////////////////////////////////////////////////////////*/

  function test__setActiveTemplateId() public {
    controller.setActiveTemplateId("Vault", "V2");
    assertEq(controller.activeTemplateId("Vault"), "V2");
  }

  function testFail__setActiveTemplateId_same_key() public {
    controller.setActiveTemplateId("Vault", "V1");
  }

  function testFail__setActiveTemplateId_nonOwner() public {
    vm.prank(nonOwner);
    controller.setActiveTemplateId("Vault", "V2");
  }
}
