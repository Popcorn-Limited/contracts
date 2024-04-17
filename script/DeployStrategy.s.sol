// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";
import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";

contract InitializeStrategy is Script {
    address deployer;

    bytes4[8] sigs;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        IAdapter(0xdce45fEab60668195D891242914864837Aa22d8d).initialize(
            abi.encode(
                IERC20(0x625E92624Bc2D88619ACCc1788365A69767f6200),
                0x22f5413C075Ccd56D575A54763831C4c27A37Bdb,
                address(0),
                0,
                sigs,
                ""
            ),
            0xd061D61a4d941c39E5453435B6345Dc261C2fcE0,
            abi.encode(0xf69Fb60B79E463384b40dbFDFB633AB5a863C9A2)
        );

        vm.stopBroadcast();
    }
}
