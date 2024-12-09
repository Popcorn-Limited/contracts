// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script, console} from "forge-std/Script.sol";
import {AsyncVault, Fees} from "src/vaults/multisig/phase1/AsyncVault.sol";

contract SetFees is Script {
    address[] vaults;
    Fees[] fees;

    function run() public {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        vaults = [0x7D40d6fefaA59668B54Cb15Ce342fe975D78B6fd];

        fees.push(
            Fees({
                managementFee: 2e16,
                performanceFee: 2e17,
                withdrawalIncentive: 0,
                feesUpdatedAt: 0,
                highWaterMark: 0,
                feeRecipient: 0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E
            })
        );

        for (uint256 i; i < vaults.length; i++) {
            AsyncVault(vaults[i]).setFees(fees[i]);
        }

        vm.stopBroadcast();
    }
}
