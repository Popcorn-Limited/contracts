// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IDeploymentController} from "../src/interfaces/vault/IDeploymentController.sol";
import {Template} from "../src/vault/TemplateRegistry.sol";

contract AddTemplate is Script {
    address deployer;

    VaultController controller =
        VaultController(0xa199409F99bDBD998Ae1ef4FdaA58b356370837d);
    IDeploymentController deploymentController =
        IDeploymentController(0xa8C5815f6Ea5F7A1551541B0d7F970D546126bDB);

    bytes32 templateCategory = "Adapter";
    bytes32 templateId = "OusdAdapter";

    bytes4[8] requiredSigs;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        deploymentController.addTemplate(
            templateCategory,
            templateId,
            Template({
                implementation: address(0xD3FFeD2025320453A937a77f19128DD1AcC25d32),
                endorsed: false,
                metadataCid: "",
                requiresInitData: true,
                registry: address(0x7a33b5b57C8b235A3519e6C010027c5cebB15CB4),
                requiredSigs: requiredSigs
            })
        );

        bytes32[] memory templateCategories = new bytes32[](1);
        bytes32[] memory templateIds = new bytes32[](1);
        templateCategories[0] = templateCategory;
        templateIds[0] = templateId;

        controller.toggleTemplateEndorsements(templateCategories, templateIds);

        vm.stopBroadcast();
    }
}
