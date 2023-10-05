// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {CloneRegistry} from "../../src/vault/CloneRegistry.sol";
import {CloneFactory} from "../../src/vault/CloneFactory.sol";
import {PermissionRegistry} from "../../src/vault/PermissionRegistry.sol";
import {TemplateRegistry, Template} from "../../src/vault/TemplateRegistry.sol";
import {DeploymentController} from "../../src/vault/DeploymentController.sol";
import {VaultFactory, IAdapter, VaultInitParams, VaultMetadata} from "../../src/vault/VaultFactory.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {AdminProxy} from "../../src/vault/AdminProxy.sol";
import {VaultRegistry} from "../../src/vault/VaultRegistry.sol";

import {MultiRewardEscrow} from "../../src/utils/MultiRewardEscrow.sol";
import {MultiRewardStaking} from "../../src/utils/MultiRewardStaking.sol";

import {ICloneRegistry} from "../../src/interfaces/vault/ICloneRegistry.sol";
import {ICloneFactory} from "../../src/interfaces/vault/ICloneFactory.sol";
import {IPermissionRegistry, Permission} from "../../src/interfaces/vault/IPermissionRegistry.sol";
import {ITemplateRegistry} from "../../src/interfaces/vault/ITemplateRegistry.sol";
import {IDeploymentController} from "../../src/interfaces/vault/IDeploymentController.sol";
import {IVaultRegistry} from "../../src/interfaces/vault/IVaultRegistry.sol";
import {IAdminProxy} from "../../src/interfaces/vault/IAdminProxy.sol";
import {IVaultController, DeploymentArgs} from "../../src/interfaces/vault/IVaultController.sol";

import {IMultiRewardEscrow} from "../../src/interfaces/IMultiRewardEscrow.sol";
import {IMultiRewardStaking} from "../../src/interfaces/IMultiRewardStaking.sol";
import {IOwned} from "../../src/interfaces/IOwned.sol";
import {IPausable} from "../../src/interfaces/IPausable.sol";

import {IVault, VaultFees, IERC4626, IERC20} from "../../src/interfaces/vault/IVault.sol";

import {MockERC20} from "../utils/mocks/MockERC20.sol";
import {MockAdapter} from "../utils/mocks/MockAdapter.sol";
import {MockStrategy} from "../utils/mocks/MockStrategy.sol";

contract VaultControllerTest is Test {
    ITemplateRegistry templateRegistry;
    IVaultRegistry vaultRegistry;

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
    event TemplateAdded(
        bytes32 templateCategory,
        bytes32 templateId,
        address implementation
    );
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



    event SelectorsVerified();
    event AdapterVerified();
    event StrategySetup();
    event Initialized(uint8 version);

    function setUp() public {
        adapterImpl = address(new MockAdapter());
        strategyImpl = address(new MockStrategy());
        vaultImpl = address(new Vault());

        adminProxy = IAdminProxy(address(new AdminProxy(address(this))));

        vaultRegistry = IVaultRegistry(
            address(new VaultRegistry(address(adminProxy)))
        );

        vaultFactory = new VaultFactory(
            address(this),
            adminProxy,
            vaultRegistry
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/
    function deployAdapter() public returns (address) {
        return
            vaultFactory.deployAdapter(
                iAsset,
                DeploymentArgs({
                    id: templateId,
                    data: abi.encode(uint256(100))
                }),
                DeploymentArgs({id: "", data: ""}),
                0
            );
    }

    function deployVault() public returns (address) {
        rewardToken.mint(address(this), 10 ether);
        rewardToken.approve(address(vaultFactory), 10 ether);

        return
            vaultFactory.deployVault(
                VaultInitParams({
                    asset: iAsset,
                    adapter: IERC4626(address(0)),
                    fees: VaultFees({
                        deposit: 100,
                        withdrawal: 200,
                        management: 300,
                        performance: 400
                    }),
                    feeRecipient: feeRecipient,
                    depositLimit: type(uint256).max,
                    owner: address(this)
                }),
                DeploymentArgs({
                    id: templateId,
                    data: abi.encode(uint256(100))
                }),
                DeploymentArgs({id: "MockStrategy", data: ""}),
                true,
                abi.encode(
                    address(rewardToken),
                    0.1 ether,
                    1 ether,
                    true,
                    10000000,
                    2 days,
                    1 days
                ),
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
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public {
        assertEq(
            address(vaultFactory.deploymentController()),
            address(deploymentController)
        );
        assertEq(
            address(vaultFactory.permissionRegistry()),
            address(permissionRegistry)
        );
        assertEq(address(vaultFactory.vaultRegistry()), address(vaultRegistry));
        assertEq(address(vaultFactory.adminProxy()), address(adminProxy));
        assertEq(address(vaultFactory.escrow()), address(escrow));

        assertEq(vaultFactory.activeTemplateId("Staking"), "MultiRewardStaking");
        assertEq(vaultFactory.activeTemplateId("Vault"), "V1");

        assertEq(vaultFactory.owner(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function test__deployVault() public {
        addTemplate("Adapter", templateId, adapterImpl, true, true);
        addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
        addTemplate("Vault", "V1", vaultImpl, true, true);
        vaultFactory.setPerformanceFee(uint256(1000));
        vaultFactory.setHarvestCooldown(1 days);
        rewardToken.mint(address(this), 10 ether);
        rewardToken.approve(address(vaultFactory), 10 ether);

        swapTokenAddresses[0] = address(0x9999);
        address adapterClone = 0xD6C5fA22BBE89db86245e111044a880213b35705;
        address strategyClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
        address stakingClone = 0xE64C695617819cE724c1d35a37BCcFbF5586F752;

        uint256 callTimestamp = block.timestamp;
        address vaultClone = vaultFactory.deployVault(
            VaultInitParams({
                asset: iAsset,
                adapter: IERC4626(address(0)),
                fees: VaultFees({
                    deposit: 100,
                    withdrawal: 200,
                    management: 300,
                    performance: 400
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: address(this)
            }),
            DeploymentArgs({id: templateId, data: abi.encode(uint256(100))}),
            DeploymentArgs({id: "MockStrategy", data: ""}),
            true,
            abi.encode(
                address(rewardToken),
                0.1 ether,
                1 ether,
                true,
                10000000,
                2 days,
                1 days
            ),
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
        assertEq(
            vaultRegistry.getVault(vaultClone).swapTokenAddresses[0],
            address(0x9999)
        );
        assertEq(
            vaultRegistry.getVault(vaultClone).swapAddress,
            address(0x5555)
        );
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

        assertEq(
            IMultiRewardStaking(stakingClone).rewardInfos(iRewardToken).ONE,
            1 ether
        );
        assertEq(
            IMultiRewardStaking(stakingClone)
                .rewardInfos(iRewardToken)
                .rewardsPerSecond,
            0.1 ether
        );
        assertEq(
            uint256(
                IMultiRewardStaking(stakingClone)
                    .rewardInfos(iRewardToken)
                    .rewardsEndTimestamp
            ),
            callTimestamp + 10
        );
        assertEq(
            uint256(
                IMultiRewardStaking(stakingClone)
                    .rewardInfos(iRewardToken)
                    .index
            ),
            1 ether
        );
        assertEq(
            uint256(
                IMultiRewardStaking(stakingClone)
                    .rewardInfos(iRewardToken)
                    .lastUpdatedTimestamp
            ),
            callTimestamp
        );

        assertEq(
            uint256(
                IMultiRewardStaking(stakingClone)
                    .escrowInfos(iRewardToken)
                    .escrowPercentage
            ),
            10000000
        );
        assertEq(
            uint256(
                IMultiRewardStaking(stakingClone)
                    .escrowInfos(iRewardToken)
                    .escrowDuration
            ),
            2 days
        );
        assertEq(
            uint256(
                IMultiRewardStaking(stakingClone)
                    .escrowInfos(iRewardToken)
                    .offset
            ),
            1 days
        );
    }

    function test__deployVault_without_strategy() public {
        addTemplate("Adapter", templateId, adapterImpl, true, true);
        addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
        addTemplate("Vault", "V1", vaultImpl, true, true);
        vaultFactory.setPerformanceFee(uint256(1000));
        vaultFactory.setHarvestCooldown(1 days);
        rewardToken.mint(address(this), 10 ether);
        rewardToken.approve(address(vaultFactory), 10 ether);

        swapTokenAddresses[0] = address(0x9999);
        address adapterClone = 0xe8a41C57AB0019c403D35e8D54f2921BaE21Ed66;
        address stakingClone = 0x949DEa045FE979a11F0D4A929446F83072D81095;

        uint256 callTimestamp = block.timestamp;
        address vaultClone = vaultFactory.deployVault(
            VaultInitParams({
                asset: iAsset,
                adapter: IERC4626(address(0)),
                fees: VaultFees({
                    deposit: 100,
                    withdrawal: 200,
                    management: 300,
                    performance: 400
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: address(this)
            }),
            DeploymentArgs({id: templateId, data: abi.encode(uint256(100))}),
            DeploymentArgs({id: "", data: ""}),
            true,
            abi.encode(
                address(rewardToken),
                0.1 ether,
                1 ether,
                true,
                10000000,
                2 days,
                1 days
            ),
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


    function test__deployVault_adapter_given() public {
        addTemplate("Adapter", templateId, adapterImpl, true, true);
        addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
        addTemplate("Vault", "V1", vaultImpl, true, true);
        vaultFactory.setPerformanceFee(uint256(1000));
        vaultFactory.setHarvestCooldown(1 days);
        rewardToken.mint(address(this), 10 ether);
        rewardToken.approve(address(vaultFactory), 10 ether);

        swapTokenAddresses[0] = address(0x9999);
        address stakingClone = 0x949DEa045FE979a11F0D4A929446F83072D81095;

        address adapterClone = vaultFactory.deployAdapter(
            iAsset,
            DeploymentArgs({id: templateId, data: abi.encode(uint256(300))}),
            DeploymentArgs({id: "", data: ""}),
            0
        );

        uint256 callTimestamp = block.timestamp;
        address vaultClone = vaultFactory.deployVault(
            VaultInitParams({
                asset: iAsset,
                adapter: IERC4626(address(adapterClone)),
                fees: VaultFees({
                    deposit: 100,
                    withdrawal: 200,
                    management: 300,
                    performance: 400
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: address(this)
            }),
            DeploymentArgs({id: "", data: ""}),
            DeploymentArgs({id: "", data: ""}),
            true,
            abi.encode(
                address(rewardToken),
                0.1 ether,
                1 ether,
                true,
                10000000,
                2 days,
                1 days
            ),
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

    function testFail__deployVault_without_adapter_nor_adapterData() public {
        addTemplate("Adapter", templateId, adapterImpl, true, true);
        addTemplate("Strategy", "MockStrategy", strategyImpl, false, true);
        addTemplate("Vault", "V1", vaultImpl, true, true);
        vaultFactory.setPerformanceFee(uint256(1000));
        vaultFactory.setHarvestCooldown(1 days);

        vaultFactory.deployVault(
            VaultInitParams({
                asset: iAsset,
                adapter: IERC4626(address(0)),
                fees: VaultFees({
                    deposit: 100,
                    withdrawal: 200,
                    management: 300,
                    performance: 400
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: address(this)
            }),
            DeploymentArgs({id: "", data: ""}),
            DeploymentArgs({id: "", data: ""}),
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

}
