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
        VaultController(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);

    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    address[8] swapTokenAddresses;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        //setPermission(0xFF504594eDd93E09309d5EAB775e7c35f642931B, true, false);

        address adapter = controller.deployVault(
            VaultInitParams({
                asset: IERC20(0x5271045F7B73c17825A7A7aee6917eE46b0B7520),
                adapter: IERC4626(address(0)),
                fees: VaultFees({
                    deposit: 0,
                    withdrawal: 0,
                    management: 0,
                    performance: 1e17
                }),
                feeRecipient: feeRecipient,
                depositLimit: type(uint256).max,
                owner: deployer
            }),
            DeploymentArgs({
                id: "YearnFactoryAdapter",
                data: abi.encode(0x06f691180F643B35E3644a2296a4097E1f577d0d, 1)
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
