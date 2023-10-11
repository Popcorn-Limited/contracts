//// SPDX-License-Identifier: GPL-3.0
//// Docgen-SOLC: 0.8.15
//pragma solidity ^0.8.15;
//
//import {Script} from "forge-std/Script.sol";
//import {VaultFactory} from "../src/vault/VaultFactory.sol";
//import {IVaultFactory, DeploymentArgs} from "../src/interfaces/vault/IVaultFactory.sol";
//
//contract SwapAdapter is Script {
//    address deployer;
//
//    VaultFactory controller =
//        VaultFactory(0xa199409F99bDBD998Ae1ef4FdaA58b356370837d);
//
//    address[] vaults;
//
//    function run() public {
//        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//        deployer = vm.addr(deployerPrivateKey);
//
//        vm.startBroadcast(deployerPrivateKey);
//
//        vaults.push(0x5d344226578DC100b2001DA251A4b154df58194f);
//
//        controller.changeVaultAdapters(vaults);
//        vm.stopBroadcast();
//    }
//}
