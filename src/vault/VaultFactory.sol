// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Owned} from "../utils/Owned.sol";
import {IVault} from "../interfaces/vault/IVault.sol";
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

    bytes32 public immutable VAULT = "Vault";
    bytes32 public immutable STRATEGY = "Strategy";

    /**
     * @notice Constructor of this contract.
     * @param _owner Owner of the contract. Controls management functions.
     * @param _vaultRegistry `VaultRegistry` to safe vault metadata.
     * @param _templateRegistry registry for strategies that a vault can use.
     * @param implementation address of the vault's implementation contract.
     */
    constructor(
        address _owner,
        IVaultRegistry _vaultRegistry,
        ITemplateRegistry _templateRegistry,
        address implementation
    ) Owned(_owner) {
        vaultRegistry = _vaultRegistry;
        templateRegistry = _templateRegistry;
        vaultImplementation = implementation;
    }

    event VaultImplementationUpdated(address old, address updated);

    function setImplementation(address implementation) external onlyOwner {
        emit VaultImplementationUpdated(vaultImplementation, implementation);
        vaultImplementation = implementation;

    }

    /*//////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/
    error InvalidConfig();
    error VaultDeploymentFailed();
    error NotAllowed(address subject);

    event VaultDeployed(
        address indexed vault,
        address indexed strategy
    );

    /**
     * @notice Deploy a new Vault.
     * @param vaultData Vault init params.
     * @param strategy the strategy address.
     * @param metadata Vault metadata for the `VaultRegistry` (Will be used by the frontend for additional informations)
     */
    function deployVault(
        BaseVaultConfig memory vaultData,
        address strategy,
        VaultMetadata memory metadata
    ) external returns (address vault) {
        require(templateRegistry.templates(VERSION, strategy), "passed strategy is not valid");

        vault = Clones.clone(vaultImplementation);
        (bool success, ) = IVault(vault).initialize(vaultData, strategy);
        if(!success) revert VaultDeploymentFailed();

        address staking;
        metadata.vault = vault;
        metadata.staking = staking;
        metadata.creator = msg.sender;

        vaultRegistry.registerVault(metadata);

        emit VaultDeployed(vault, strategy);
    }

}
