// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {OracleVault} from "src/vaults/multisig/phase1/OracleVault.sol";
import {InitializeParams, Limits, Fees} from "src/vaults/multisig/phase1/AsyncVault.sol";
import {OracleVaultController} from "src/peripheral/oracles/OracleVaultController.sol";
import {IOwned} from "src/interfaces/IOwned.sol";

interface IOracleVaultController {
    function addVault(address vault) external;
    function setKeeper(address vault, address keeper) external;
}

contract Deploy is Script {
    address internal asset;

    string internal name;
    string internal symbol;

    address internal owner;

    Limits internal limits;
    Fees internal fees;

    address internal oracle;
    address internal multisig;

    address[] internal keepers;
    address internal oracleController;

    function run() public returns (OracleVault vault) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        name = "Safe Vault";
        symbol = "sVault";

        // @dev edit the values below
        asset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        limits = Limits(type(uint256).max, 0);
        fees = Fees(0, 0, 0, 0, 0, msg.sender);

        oracle = 0x31f687C0F28bB10b0296DE15792407f6C0d62F5D;

        // edge arb,eth
        multisig = 0x35902EcbB6691913470840F221852f363137366F;

        owner = msg.sender;

        keepers = [
            0xE015c099a3E731757dC33491eFb1E8Eb883aCA8B,
            0x35902EcbB6691913470840F221852f363137366F
        ];

        oracleController = 0xDF9b9c1151587D5c087cE208B38aea5a68083110;

        // Actual deployment
        vault = new OracleVault(
            InitializeParams(asset, name, symbol, owner, limits, fees),
            oracle,
            multisig
        );

        // Oracle Vault Controller setup
        address controller = IOwned(oracle).owner();
        IOracleVaultController(controller).addVault(address(vault));

        for (uint256 i = 0; i < keepers.length; i++) {
            IOracleVaultController(controller).setKeeper(
                address(vault),
                keepers[i]
            );
        }

        vault.updateRole(vault.PAUSER_ROLE(), oracleController, true);

        vm.stopBroadcast();
    }
}
