// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Owned} from "../utils/Owned.sol";
import {IVault, VaultFees, IERC4626, IERC20} from "../interfaces/vault/IVault.sol";
import {IMultiRewardStaking} from "../interfaces/IMultiRewardStaking.sol";
import {IMultiRewardEscrow} from "../interfaces/IMultiRewardEscrow.sol";
import {IDeploymentController, ICloneRegistry} from "../interfaces/vault/IDeploymentController.sol";
import {ITemplateRegistry, Template} from "../interfaces/vault/ITemplateRegistry.sol";
import {IPermissionRegistry, Permission} from "../interfaces/vault/IPermissionRegistry.sol";
import {IVaultRegistry, VaultMetadata} from "../interfaces/vault/IVaultRegistry.sol";
import {IAdminProxy} from "../interfaces/vault/IAdminProxy.sol";
import {IStrategy} from "../interfaces/vault/IStrategy.sol";
import {IAdapter} from "../interfaces/vault/IAdapter.sol";
import {IPausable} from "../interfaces/IPausable.sol";
import {DeploymentArgs} from "../interfaces/vault/IVaultController.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import {BaseVaultConfig} from "./v2/base/BaseVault.sol";

/**
 * @title   VaultController
 * @author  RedVeil
 * @notice  Admin contract for the vault ecosystem.
 *
 * Deploys Vaults, Adapter, Strategies and Staking contracts.
 * Calls admin functions on deployed contracts.
 */
contract VaultFactory is Owned {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    IVaultRegistry public vaultRegistry;

    bytes32 public immutable VAULT = "Vault";
    bytes32 public immutable ADAPTER = "Adapter";
    bytes32 public immutable STRATEGY = "Strategy";
    bytes32 public immutable STAKING = "Staking";
    bytes4 internal immutable DEPLOY_SIG =
        bytes4(keccak256("deploy(bytes32,bytes32,bytes)"));

    /**
     * @notice Constructor of this contract.
     * @param _owner Owner of the contract. Controls management functions.
     * @param _adminProxy `AdminProxy` ownes contracts in the vault ecosystem.
     * @param _deploymentController `DeploymentController` with auxiliary deployment contracts.
     * @param _vaultRegistry `VaultRegistry` to safe vault metadata.
     * @param _permissionRegistry `permissionRegistry` to add endorsements and rejections.
     * @param _escrow `MultiRewardEscrow` To escrow rewards of staking contracts.
     */
    constructor(
        address _owner,
        IAdminProxy _adminProxy,
        IDeploymentController _deploymentController,
        IVaultRegistry _vaultRegistry,
        IPermissionRegistry _permissionRegistry,
        IMultiRewardEscrow _escrow
    ) Owned(_owner) {
        adminProxy = _adminProxy;
        vaultRegistry = _vaultRegistry;
        permissionRegistry = _permissionRegistry;
        escrow = _escrow;

        _setDeploymentController(_deploymentController);

        activeTemplateId[STAKING] = "MultiRewardStaking";
        activeTemplateId[VAULT] = "V1";
    }

    /*//////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    error InvalidConfig();
    error VaultDeploymentFailed();
    error NotAllowed(address subject);

    event VaultDeployed(
        address indexed vault,
        address indexed staking,
        address indexed adapter
    );

    modifier canCreate() {
        if (
            permissionRegistry.endorsed(address(1))
                ? !permissionRegistry.endorsed(msg.sender)
                : permissionRegistry.rejected(msg.sender)
        ) revert NotAllowed(msg.sender);
        _;
    }

    /**
     * @notice Deploy a new Vault. Optionally with an Adapter and Staking. Caller must be owner.
     * @param vaultData Vault init params.
     * @param adapterData Encoded adapter init data.
     * @param strategyData Encoded strategy init data.
     * @param rewardsData Encoded data to add a rewards to the staking contract
     * @param metadata Vault metadata for the `VaultRegistry` (Will be used by the frontend for additional informations)
     * @param initialDeposit Initial deposit to the vault. If 0, no deposit will be made.
     * @dev This function is the one stop solution to create a new vault with all necessary admin functions or auxiliery contracts.
     */
    function deployVault(
        BaseVaultConfig memory vaultData,
        DeploymentArgs memory adapterData,
        DeploymentArgs memory strategyData,
        bytes memory rewardsData,
        VaultMetadata memory metadata,
        uint256 initialDeposit
    ) external canCreate returns (address vault) {
        IDeploymentController _deploymentController = deploymentController;

        _verifyToken(address(vaultData.asset));
        if (
            address(vaultData.adapter) != address(0) &&
            (adapterData.id > 0 ||
                !cloneRegistry.cloneExists(address(vaultData.adapter)))
        ) revert InvalidConfig();

        vault = _deployVault(vaultData, _deploymentController);

        address staking;
        metadata.vault = vault;
        metadata.staking = staking;
        metadata.creator = msg.sender;
        _registerVault(vault, metadata);

        emit VaultDeployed(vault, staking, address(vaultData.adapter));
    }

    /// @notice Deploys a new vault contract using the `activeTemplateId`.
    function _deployVault(
        BaseVaultConfig memory _vaultData
    ) internal returns (address vault) {
        Template memory template = templateRegistry.getTemplate(VAULT, activeTemplateId[VAULT]);
        if (!template.endorsed) revert NotEndorsed(templateId);

        vault = Clones.clone(template.implementation);
        //TODO: fetch the strategy data from template and add to init data
        (bool success, ) = vault.call(abi.encodeWithSelector(IVault.initialize.selector, _vaultData));
        if(!success) revert VaultDeploymentFailed();
    }

    /*//////////////////////////////////////////////////////////////
                          REGISTER VAULT
    //////////////////////////////////////////////////////////////*/

    /// @notice Call the `VaultRegistry` to register a vault via `AdminProxy`
    function _registerVault(
        address vault,
        VaultMetadata memory metadata
    ) internal {
        adminProxy.execute(
            address(vaultRegistry),
            abi.encodeWithSelector(
                IVaultRegistry.registerVault.selector,
                metadata
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                          MANAGEMENT FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;

    event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);

    error InvalidPerformanceFee(uint256 fee);

    /**
     * @notice Set a new performanceFee for all new adapters. Caller must be owner.
     * @param newFee performance fee in 1e18.
     * @dev Fees can be 0 but never more than 2e17 (1e18 = 100%, 1e14 = 1 BPS)
     * @dev Can be retroactively applied to existing adapters.
     */
    function setPerformanceFee(uint256 newFee) external onlyOwner {
        // Dont take more than 20% performanceFee
        if (newFee > 2e17) revert InvalidPerformanceFee(newFee);

        emit PerformanceFeeChanged(performanceFee, newFee);

        performanceFee = newFee;
    }

    /**
     * @notice Set a new performanceFee for existing adapters. Caller must be owner.
     * @param adapters array of adapters to set the management fee for.
     */
    function setAdapterPerformanceFees(
        address[] calldata adapters
    ) external onlyOwner {
        uint8 len = uint8(adapters.length);
        for (uint256 i = 0; i < len; i++) {
            adminProxy.execute(
                adapters[i],
                abi.encodeWithSelector(
                    IAdapter.setPerformanceFee.selector,
                    performanceFee
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                            HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public harvestCooldown;

    event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);

    error InvalidHarvestCooldown(uint256 cooldown);

    /**
     * @notice Set a new harvestCooldown for all new adapters. Caller must be owner.
     * @param newCooldown Time in seconds that must pass before a harvest can be called again.
     * @dev Cant be longer than 1 day.
     * @dev Can be retroactively applied to existing adapters.
     */
    function setHarvestCooldown(uint256 newCooldown) external onlyOwner {
        // Dont wait more than X seconds
        if (newCooldown > 1 days) revert InvalidHarvestCooldown(newCooldown);

        emit HarvestCooldownChanged(harvestCooldown, newCooldown);

        harvestCooldown = newCooldown;
    }

    /**
     * @notice Set a new harvestCooldown for existing adapters. Caller must be owner.
     * @param adapters Array of adapters to set the cooldown for.
     */
    function setAdapterHarvestCooldowns(
        address[] calldata adapters
    ) external onlyOwner {
        uint8 len = uint8(adapters.length);
        for (uint256 i = 0; i < len; i++) {
            adminProxy.execute(
                adapters[i],
                abi.encodeWithSelector(
                    IAdapter.setHarvestCooldown.selector,
                    harvestCooldown
                )
            );
        }
    }

    /**
     * @notice Toggle `AutoHarvest` existing adapters. Caller must be owner.
     * @param adapters Array of adapters to set the autoHarvest value for.
     */
    function toggleAdapterAutoHarvest(
        address[] calldata adapters
    ) external onlyOwner {
        uint8 len = uint8(adapters.length);
        for (uint256 i = 0; i < len; i++) {
            adminProxy.execute(
                adapters[i],
                abi.encodeWithSelector(IAdapter.toggleAutoHarvest.selector)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                      TEMPLATE KEY LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 => bytes32) public activeTemplateId;

    event ActiveTemplateIdChanged(bytes32 oldKey, bytes32 newKey);

    error SameKey(bytes32 templateKey);

    /**
     * @notice Set a templateId which shall be used for deploying certain contracts. Caller must be owner.
     * @param templateCategory TemplateCategory to set an active key for.
     * @param templateId TemplateId that should be used when creating a new contract of `templateCategory`
     * @dev Currently `Vault` and `Staking` use a template set via `activeTemplateId`.
     * @dev If this contract should deploy Vaults of a second generation this can be set via the `activeTemplateId`.
     */
    function setActiveTemplateId(
        bytes32 templateCategory,
        bytes32 templateId
    ) external onlyOwner {
        bytes32 oldTemplateId = activeTemplateId[templateCategory];
        if (oldTemplateId == templateId) revert SameKey(templateId);

        emit ActiveTemplateIdChanged(oldTemplateId, templateId);

        activeTemplateId[templateCategory] = templateId;
    }
}
