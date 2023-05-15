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
        VaultController(0x757D953c53aD28748aCf94AD2d59C13955E09c08);

    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    address[8] swapTokenAddresses;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        setPermission(0xFF504594eDd93E09309d5EAB775e7c35f642931B, true, false);

        address adapter = controller.deployVault(
            VaultInitParams({
                asset: IERC20(0x207AddB05C548F262219f6bFC6e11c02d0f7fDbe),
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
            DeploymentArgs({
                id: "BeefyAdapter",
                data: abi.encode(
                    address(0xFF504594eDd93E09309d5EAB775e7c35f642931B),
                    address(0)
                )
            }),
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
