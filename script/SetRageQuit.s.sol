// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {VaultFactory, IAdapter, VaultInitParams, VaultMetadata, IERC4626, IERC20, VaultFees} from "../src/vault/VaultFactory.sol";

contract SetRageQuit is Script {
    address deployer;

    address[] internal vaults;
    uint256[] internal periods;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        vaults = [
            0xDFd505B54E15D5B20842e868E4c19D7b6F0a4a5d,
            0xB38b9522005ffBb0e297c17A8e2a3f11C6433e8C
        ];
        periods = [1 days, 1 days];

        VaultFactory(0x9Ec0BEfBf3d8860B3e1715fb407b66186fe1E702)
            .setVaultQuitPeriods(vaults, periods);

        vm.stopBroadcast();
    }
}
