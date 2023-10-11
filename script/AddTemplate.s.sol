//// SPDX-License-Identifier: GPL-3.0
//// Docgen-SOLC: 0.8.15
//pragma solidity ^0.8.15;
//
//import {Script} from "forge-std/Script.sol";
//import {VaultFactory, VaultMetadata} from "../src/vault/VaultFactory.sol";
//import {IDeploymentController} from "../src/interfaces/vault/IDeploymentController.sol";
//import {Template} from "../src/vault/TemplateRegistry.sol";
//
//contract AddTemplate is Script {
//    address deployer;
//
//    VaultFactory controller =
//        VaultFactory(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);
//    IDeploymentController deploymentController =
//        IDeploymentController(0xa8C5815f6Ea5F7A1551541B0d7F970D546126bDB);
//
//    bytes32 templateCategory = "Adapter";
//    bytes32 templateId = "YearnFactoryAdapter";
//
//    bytes4[8] requiredSigs;
//
//    function run() public {
//        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//        deployer = vm.addr(deployerPrivateKey);
//
//        vm.startBroadcast(deployerPrivateKey);
//
//        deploymentController.addTemplate(
//            templateCategory,
//            templateId,
//            Template({
//                implementation: address(0xcA227F32917cEC6c579b0030920B47387e8fBD10),
//                endorsed: false,
//                metadataCid: "",
//                requiresInitData: true,
//                registry: address(0x21b1FC8A52f179757bf555346130bF27c0C2A17A),
//                requiredSigs: requiredSigs
//            })
//        );
//
//        bytes32[] memory templateCategories = new bytes32[](1);
//        bytes32[] memory templateIds = new bytes32[](1);
//        templateCategories[0] = templateCategory;
//        templateIds[0] = templateId;
//
//        controller.toggleTemplateEndorsements(templateCategories, templateIds);
//
//        vm.stopBroadcast();
//    }
//}
