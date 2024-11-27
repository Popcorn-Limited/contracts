// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {OracleVaultController, Limit} from "src/peripheral/oracles/OracleVaultController.sol";

contract SetLimits is Script {
    address[] vaults;
    Limit[] limits;

    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        vaults = [
            0x92f60021b107867b970DE439D93f023E472947A8,
            0x872418226D8Dbd423084007f33B8e242D5C3c074
        ];

        limits.push(Limit({jump: 1e17, drawdown: 1e17}));
        limits.push(Limit({jump: 1e17, drawdown: 1e17}));

        OracleVaultController(0xDF9b9c1151587D5c087cE208B38aea5a68083110)
            .setLimits(vaults, limits);

        vm.stopBroadcast();
    }
}
