// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultFactory, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultFactory.sol";
import {IVaultController, DeploymentArgs} from "../src/interfaces/vault/IVaultController.sol";

contract ProposeVaultFees is Script {
    address deployer;

    VaultFactory controller =
        VaultFactory(0x7D51BABA56C2CA79e15eEc9ECc4E92d9c0a7dbeb);

    address[] vaults;
    VaultFees[] fees;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // vaults.push(0x5d344226578DC100b2001DA251A4b154df58194f);
        // vaults.push(0xc1D4a319dD7C44e332Bd54c724433C6067FeDd0D);
        // vaults.push(0xb6cED1C0e5d26B815c3881038B88C829f39CE949);
        // vaults.push(0x2fD2C18f79F93eF299B20B681Ab2a61f5F28A6fF);
        // vaults.push(0xc8C88fdF2802733f8c4cd7c0bE0557fdC5d2471c);
        // vaults.push(0xBae30fBD558A35f147FDBaeDbFF011557d3C8bd2);


        fees.push(
            VaultFees({
                deposit: 0,
                withdrawal: 0,
                management: 0,
                performance: 1e17
            })
        );
        // fees.push(
        //     VaultFees({
        //         deposit: 0,
        //         withdrawal: 0,
        //         management: 0,
        //         performance: 1e17
        //     })
        // );
        // fees.push(
        //     VaultFees({
        //         deposit: 0,
        //         withdrawal: 0,
        //         management: 0,
        //         performance: 1e17
        //     })
        // );
        // fees.push(
        //     VaultFees({
        //         deposit: 0,
        //         withdrawal: 0,
        //         management: 0,
        //         performance: 1e17
        //     })
        // );
        // fees.push(
        //     VaultFees({
        //         deposit: 0,
        //         withdrawal: 0,
        //         management: 0,
        //         performance: 1e17
        //     })
        // );
        // fees.push(
        //     VaultFees({
        //         deposit: 0,
        //         withdrawal: 0,
        //         management: 0,
        //         performance: 1e17
        //     })
        // );

        controller.proposeVaultFees(vaults, fees);

        vm.stopBroadcast();
    }
}
