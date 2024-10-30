// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {OracleVault} from "src/vaults/multisig/phase1/OracleVault.sol";
import {InitializeParams, Limits, Fees} from "src/vaults/multisig/phase1/AsyncVault.sol";

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

        // @dev edit this values below
        asset = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

        name = "Oracle Vault";
        symbol = "oVault";

        limits = Limits(type(uint256).max, 0);
        fees = Fees(0, 0, 0, 0, 0, msg.sender);

        oracle = 0xf7C42Db8bdD563539861de0ef2520Aa80c28e8c4;

        multisig = 0x3C99dEa58119DE3962253aea656e61E5fBE21613;

        owner = msg.sender;

        // Actual deployment
        vault = new OracleVault(
            InitializeParams(asset, name, symbol, owner, limits, fees),
            oracle,
            multisig
        );

        vm.stopBroadcast();
    }
}
