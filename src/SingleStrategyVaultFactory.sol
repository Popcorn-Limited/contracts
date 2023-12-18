// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Owned} from "./utils/Owned.sol";
import {IVault} from "./base/interfaces/IVault.sol";
import {ITemplateRegistry} from "./base/interfaces/ITemplateRegistry.sol";
import {IVaultRegistry} from "./base/interfaces/IVaultRegistry.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {BaseVaultConfig} from "./base/BaseVault.sol";
import {SingleStrategyVault} from "./vaults/SingleStrategyVault.sol";

/**
 * @title   VaultController
 * @author  RedVeil
 * @notice  Admin contract for the vault ecosystem.
 *
 * Deploys Vaults, Adapter, Strategies and Staking contracts.
 * Calls admin functions on deployed contracts.
 */
contract SingleStrategyVaultFactory is Owned {

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    IVaultRegistry public vaultRegistry;
    IVaultRegistry public customStrategyVaultRegistry;
    ITemplateRegistry public templateRegistry;
    address public vaultImplementation;

    bytes32 public constant VERSION = "v2.0.0";

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error VaultDeploymentFailed();
    error InvalidStrategy();
    error NotAVault();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event VaultDeployed(address indexed vault);
    event CustomStrategyVaultDeployed(address indexed vault); 
    event VaultImplementationUpdated(address indexed oldVault, address indexed newVault);
    event VaultMigrated(address indexed vault);

    /**
     * @notice Constructor of this contract.
     * @param _owner Owner of the contract. Controls management functions.
     * @param _vaultRegistry `VaultRegistry` to safe vault metadata.
     * @param _templateRegistry registry for strategies that a vault can use.
     */
    constructor(
        address _owner,
        IVaultRegistry _vaultRegistry,
        IVaultRegistry _customStrategyVaultRegistry,
        ITemplateRegistry _templateRegistry,
        address vault
    ) Owned(_owner) {
        vaultRegistry = _vaultRegistry;
        customStrategyVaultRegistry = _customStrategyVaultRegistry;
        templateRegistry = _templateRegistry;
        vaultImplementation = vault;
    }

    function updateVaultImplementation(address newVault) external onlyOwner {
        address oldVault = vaultImplementation;
        vaultImplementation = newVault;

        emit VaultImplementationUpdated(oldVault, newVault);
    }


    /*//////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    event VaultDeployed(
        address indexed vault,
        address indexed strategy
    );

    /**
     * @notice Deploy a new Vault.
     * @param vaultData Vault init params.
     * @param strategy the strategy contract
     */
    function deployVault(
        BaseVaultConfig memory vaultData,
        address strategy
    ) external returns (address vault) {
        if (!templateRegistry.templates(VERSION, strategy)) revert InvalidStrategy();

        vault = Clones.clone(vaultImplementation);
        IVault(vault).initialize(vaultData, strategy);

        vaultRegistry.registerVault(vault, msg.sender);

        emit VaultDeployed(vault);
    }

    function deployCustomStrategyVault(
        BaseVaultConfig memory vaultData,
        address strategy
    ) external returns (address vault) {
        vault = Clones.clone(vaultImplementation);
        IVault(vault).initialize(vaultData, strategy);

        customStrategyVaultRegistry.registerVault(vault, msg.sender);

        emit CustomStrategyVaultDeployed(vault);
    }

    function migrateVault(address vault) external {
        // check whether the given address is a valid custom strategy vault
        if (!customStrategyVaultRegistry.vaults(vault)) revert NotAVault();
        // check whether the vault's strategy is registered in the TemplateRegistry
        if (!templateRegistry.templates(VERSION, address(SingleStrategyVault(vault).strategy()))) revert InvalidStrategy();
    
        vaultRegistry.registerVault(vault, msg.sender);

        emit VaultMigrated(vault);
    }
}
