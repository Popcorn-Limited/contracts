// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {IVault, VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";
import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";

contract InitializeVault is Script {
    address deployer;

    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        IVault(0xE3514a5e431442D794A1aa738aC94984B593C799).initialize(
            IERC20(0x625E92624Bc2D88619ACCc1788365A69767f6200),
            IERC4626(0xdce45fEab60668195D891242914864837Aa22d8d),
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 1e17
            }),
            feeRecipient,
            type(uint256).max,
            deployer
        );

        vm.stopBroadcast();
    }
}
