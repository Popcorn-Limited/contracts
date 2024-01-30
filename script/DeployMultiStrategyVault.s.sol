// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {MultiStrategyVault, IERC4626, IERC20, VaultFees} from "../src/vaults/MultiStrategyVault.sol";
import {IPermissionRegistry, Permission} from "../src/interfaces/vault/IPermissionRegistry.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";

contract DeployMultiStrategyVault is Script {
    address deployer;

    VaultController controller =
        VaultController(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);

    address feeRecipient = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    IERC4626[] internal strategies;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        strategies = [
            IERC4626(0x61dCd1Da725c0Cdb2C6e67a0058E317cA819Cf5f),
            IERC4626(0x9168AC3a83A31bd85c93F4429a84c05db2CaEF08),
            IERC4626(0x2D0483FefAbA4325c7521539a3DFaCf94A19C472),
            IERC4626(0x6076ebDFE17555ed3E6869CF9C373Bbd9aD55d38)
        ];

        MultiStrategyVault(0xcede40B40F7AF69f5Aa6b12D75fd5eA9cE138b93)
            .initialize(
                IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F),
                strategies,
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
