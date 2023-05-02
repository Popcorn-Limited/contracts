// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultController, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultController.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";

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

        address adapter = controller.deployVault(
            VaultInitParams({
                asset: IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
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
            DeploymentArgs({id: "YearnAdapter", data: abi.encode(uint256(1))}),
            DeploymentArgs({id: "", data: ""}),
            false,
            "",
            VaultMetadata({
                vault: address(0),
                staking: address(0),
                creator: address(this),
                metadataCID: "",
                swapTokenAddresses: swapTokenAddresses,
                swapAddress: address(0),
                exchange: uint256(0)
            }),
            0
        );

        vm.stopBroadcast();
    }
}
