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

        IAdapter(0xd11A312a7d9745C62dfc014D72E7Bb2403DABf72).initialize(
            abi.encode(
                IERC20(0x0df083de449F75691fc5A36477a6f3284C269108),
                0x22f5413C075Ccd56D575A54763831C4c27A37Bdb,
                address(0),
                0,
                sigs,
                ""
            ),
            0xf5862457AA842605f8b675Af13026d3Fd03bFfF0,
            abi.encode(0x36691b39Ec8fa915204ba1e1A4A3596994515639, 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858)
        );

        vm.stopBroadcast();
    }
}
