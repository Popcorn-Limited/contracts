//// SPDX-License-Identifier: GPL-3.0
//// Docgen-SOLC: 0.8.15
//pragma solidity ^0.8.15;
//
//import {Script} from "forge-std/Script.sol";
//import {VaultFactory} from "../src/vault/VaultFactory.sol";
//import {IVaultFactory, DeploymentArgs} from "../src/interfaces/vault/IVaultFactory.sol";
//import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";
//
//contract DeployVault is Script {
//    address deployer;
//
//    VaultFactory controller =
//        VaultFactory(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);
//
//    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);
//
//    address[8] swapTokenAddresses;
//
//    function run() public {
//        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//        deployer = vm.addr(deployerPrivateKey);
//
//        vm.startBroadcast(deployerPrivateKey);
//
//        //setPermission(0xFF504594eDd93E09309d5EAB775e7c35f642931B, true, false);
//
//        address adapter = controller.deployVault(
//            VaultInitParams({
//                asset: IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7),
//                adapter: IERC4626(address(0)),
//                fees: VaultFees({
//                    deposit: 0,
//                    withdrawal: 0,
//                    management: 0,
//                    performance: 1e17
//                }),
//                feeRecipient: feeRecipient,
//                depositLimit: type(uint256).max,
//                owner: deployer
//            }),
//            DeploymentArgs({
//                id: "IdleSeniorAdapter",
//                data: abi.encode(0xc4574C60a455655864aB80fa7638561A756C5E61)
//            }),
//            DeploymentArgs({id: "", data: ""}),
//            false,
//            "",
//            VaultMetadata({
//                vault: address(0),
//                staking: address(0),
//                creator: deployer,
//                metadataCID: "",
//                swapTokenAddresses: swapTokenAddresses,
//                swapAddress: address(0),
//                exchange: uint256(0)
//            }),
//            0
//        );
//
//        vm.stopBroadcast();
//    }
//
//    function setPermission(
//        address target,
//        bool endorsed,
//        bool rejected
//    ) public {
//        address[] memory targets = new address[](1);
//        Permission[] memory permissions = new Permission[](1);
//        targets[0] = target;
//        permissions[0] = Permission(endorsed, rejected);
//        controller.setPermissions(targets, permissions);
//    }
//}
