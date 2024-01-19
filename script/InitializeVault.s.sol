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

        IVault(0x10710562d45a5356d32aD27Eea9f61F6ec44Cc19).initialize(
            IERC20(0x0df083de449F75691fc5A36477a6f3284C269108),
            IERC4626(0xd11A312a7d9745C62dfc014D72E7Bb2403DABf72),
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
