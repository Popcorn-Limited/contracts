// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";
import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";

contract SetRageQuit is Script {
    address deployer;

    VaultController controller =
        VaultController(0xa199409F99bDBD998Ae1ef4FdaA58b356370837d);

    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    address[8] swapTokenAddresses;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // setPermission(0xD2af830E8CBdFed6CC11Bab697bB25496ed6FA62, true, false);

        address adapter = controller.deployVault(
            VaultInitParams({
                asset: IERC20(0x2A8e1E676Ec238d8A992307B495b45B3fEAa5e86),
                adapter: IERC4626(address(0)),
                fees: VaultFees({
                    deposit: 0,
                    withdrawal: 0,
                    management: 0,
                    performance: 0
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: deployer
            }),
            DeploymentArgs({id: "OusdAdapter", data: abi.encode(address(0xD2af830E8CBdFed6CC11Bab697bB25496ed6FA62))}),
            DeploymentArgs({id: "", data: ""}),
            false,
            "",
            VaultMetadata({
                vault: address(0),
                staking: address(0),
                creator: deployer,
                metadataCID: "",
                swapTokenAddresses: swapTokenAddresses,
                swapAddress: address(0),
                exchange: uint256(0)
            }),
            0
        );

        vm.stopBroadcast();
    }

    function setPermission(
        address target,
        bool endorsed,
        bool rejected
    ) public {
        address[] memory targets = new address[](1);
        Permission[] memory permissions = new Permission[](1);
        targets[0] = target;
        permissions[0] = Permission(endorsed, rejected);
        controller.setPermissions(targets, permissions);
    }
}
