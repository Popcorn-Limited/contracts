// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {OracleVault} from "src/vaults/multisig/phase1/OracleVault.sol";
import {InitializeParams, Limits, Fees} from "src/vaults/multisig/phase1/AsyncVault.sol";
import {OracleVaultController} from "src/peripheral/oracles/OracleVaultController.sol";
import {IOwned} from "src/interfaces/IOwned.sol";

contract Deploy is Script {
    address internal asset;

    string internal name;
    string internal symbol;

    address internal owner;

    Limits internal limits;
    Fees internal fees;

    address internal oracle;
    address internal multisig;

    function run() public returns (OracleVault vault) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        name = "Safe Vault";
        symbol = "sVault";

        // @dev edit the values below
        asset = 0x4200000000000000000000000000000000000006;

        limits = Limits(type(uint256).max, 0);
        fees = Fees(0, 0, 0, 0, 0, msg.sender);

        oracle = 0xa7df2Ff7a6E1FAEb480617A01aD80b99CE39Bcc3;

        // Lido arb,opt
        multisig = 0x158a006d5FBA167C8c439e010343e0603DC44847;

        owner = msg.sender;

        // Actual deployment
        vault = new OracleVault(
            InitializeParams(asset, name, symbol, owner, limits, fees),
            oracle,
            multisig
        );

        // Oracle Vault Controller setup
        address controller = IOwned(oracle).owner();
        OracleVaultController(controller).addVault(address(vault));
        OracleVaultController(controller).setKeeper(
            address(vault),
            0xE015c099a3E731757dC33491eFb1E8Eb883aCA8B
        ); // Set Gelato as Keeper

        vm.stopBroadcast();
    }
}
