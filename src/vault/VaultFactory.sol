// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Owned} from "../utils/Owned.sol";
import {IVault} from "./v2/base/interfaces/IVault.sol";
import {ITemplateRegistry} from "../interfaces/vault/ITemplateRegistry.sol";
import {IVaultRegistry, VaultMetadata} from "../interfaces/vault/IVaultRegistry.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
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

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    IVaultRegistry public vaultRegistry;
    ITemplateRegistry public templateRegistry;
    address public vaultImplementation;

    bytes32 public constant VERSION = "v2.0.0";

    bytes32 public immutable REBALANCING_VAULT = "RebalancingVault";
    bytes32 public immutable SINGLE_STRATEGY_VAULT = "SingleStrategyVault";

    bytes32 public immutable LEVERAGE_STRATEGY = "LeverageStrategy";
    bytes32 public immutable DEPOSITOR_STRATEGY = "DepositorStrategy";
    bytes32 public immutable COMPOUNDER_STRATEGY = "CompounderStrategy";
    bytes32 public immutable REWARD_CLAIMER_STRATEGY = "RewardClaimerStrategy";

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error VaultDeploymentFailed();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event VaultDeployed(address indexed vault, bytes32 indexed vaultCategory);
    event VaultRegistryUpdated(address indexed old, address indexed updated);

    /**
     * @notice Constructor of this contract.
     * @param _owner Owner of the contract. Controls management functions.
     * @param _vaultRegistry `VaultRegistry` to safe vault metadata.
     * @param _templateRegistry registry for strategies that a vault can use.
     */
    constructor(
        address _owner,
        IVaultRegistry _vaultRegistry,
        ITemplateRegistry _templateRegistry
    ) Owned(_owner) {
        vaultRegistry = _vaultRegistry;
        templateRegistry = _templateRegistry;
    }


    /*//////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deploy a new Vault.
     * @param vaultData Vault init params.
     * @param vaultCategory category of vault to deploy
     * @param strategyCategory category of strategy to deploy
     */
    function deployVault(
        BaseVaultConfig memory vaultData,
        bytes32 vaultCategory,
        bytes32 strategyCategory
    ) external returns (address vault) {
        address vaultImplementation = templateRegistry.getTemplate(VERSION, vaultCategory);
        if (address(0) == vaultImplementation) revert ZeroAddress();

        address strategyImplementation = templateRegistry.getTemplate(VERSION, strategyCategory);
        if (address(0) == strategyImplementation) revert ZeroAddress();

        vault = Clones.clone(vaultImplementation);
        IVault(vault).initialize(vaultData, strategyImplementation);

        VaultMetadata memory metadata;
        metadata.vault = vault;
        metadata.vaultCategory = vaultCategory;
        metadata.creator = msg.sender;

        vaultRegistry.registerVault(metadata);

        emit VaultDeployed(vault, vaultCategory);
    }

    /*//////////////////////////////////////////////////////////////
                          UPDATE VAULT FACTORY
    //////////////////////////////////////////////////////////////*/
    function setVaultRegistry(address newVaultRegistry) external onlyOwner {
        if(address(0) == newVaultRegistry) revert ZeroAddress();

        emit VaultRegistryUpdated(address(vaultRegistry), address(newVaultRegistry));
        vaultRegistry = IVaultRegistry(newVaultRegistry);
    }
}
