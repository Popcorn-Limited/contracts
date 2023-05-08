// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";

contract ProposeAdapter is Script {
    address deployer;

    VaultController controller =
        VaultController(0xa199409F99bDBD998Ae1ef4FdaA58b356370837d);

    address[] vaults;
    IERC4626[] adapters;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        vaults.push(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D);
        address adapter = controller.deployAdapter(
            IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            DeploymentArgs({
                id: "CompoundV2Adapter",
                data: abi.encode(0x465a5a630482f3abD6d3b84B39B29b07214d19e5)
            }),
            DeploymentArgs({id: "", data: ""}),
            0
        );
        adapters.push(IERC4626(adapter));

        controller.proposeVaultAdapters(vaults, adapters);
        vm.stopBroadcast();
    }
}
