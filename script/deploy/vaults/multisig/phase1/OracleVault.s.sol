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
        asset = 0x8BB97A618211695f5a6a889faC3546D1a573ea77;

        limits = Limits(type(uint256).max, 0);
        fees = Fees(0, 0, 0, 0, 0, msg.sender);

        oracle = 0x31f687C0F28bB10b0296DE15792407f6C0d62F5D;

        // edge arb,eth
        multisig = 0x7b514263665C3eC36e4Eb24b4B7dC95BB183D255;

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
