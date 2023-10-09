// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Owned} from "../utils/Owned.sol";
import {IVault} from "./v2/base/interfaces/IVault.sol";
import {ITemplateRegistry} from "../interfaces/vault/ITemplateRegistry.sol";
import {IVaultRegistry} from "../interfaces/vault/IVaultRegistry.sol";
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

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error VaultDeploymentFailed();
    error InvalidStrategy();

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event VaultDeployed(address indexed vault);
    event VaultImplementationUpdated(address indexed oldVault, address indexed newVault);

    /**
     * @notice Constructor of this contract.
     * @param _owner Owner of the contract. Controls management functions.
     * @param _vaultRegistry `VaultRegistry` to safe vault metadata.
     * @param _templateRegistry registry for strategies that a vault can use.
     */
    constructor(
        address _owner,
        IVaultRegistry _vaultRegistry,
        ITemplateRegistry _templateRegistry,
        address vault
    ) Owned(_owner) {
        vaultRegistry = _vaultRegistry;
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
    error VaultDeploymentFailed();

    event VaultDeployed(
        address indexed vault,
        address indexed strategy
    );

    error InvalidStrategy();

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
}
