// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";
import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";

contract DeployAdapter is Script {
    address deployer;

    VaultController controller =
        VaultController(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);

    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address adapter = controller.deployAdapter(
            IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7),
            DeploymentArgs({
                id: "IdleJuniorAdapter",
                data: abi.encode(0xc4574C60a455655864aB80fa7638561A756C5E61)
            }),
            DeploymentArgs({id: "", data: ""}),
            0
        );

        vm.stopBroadcast();
    }
}
