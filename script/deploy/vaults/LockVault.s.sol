// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {LockVault, IERC4626, IERC20} from "src/vaults/LockVault.sol";

contract Deploy is Script {
    address internal asset;
    address[] internal rewardTokens;
    address internal strategy;
    uint256 internal maxLockTime;
    string internal name;
    string internal symbol;

    function run() public returns (LockVault vault) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // @dev edit this values below
        asset = address(0xcE246eEa10988C495B4A90a905Ee9237a0f91543);

        rewardTokens = [
            address(0xcE246eEa10988C495B4A90a905Ee9237a0f91543),
            address(0xaFa52E3860b4371ab9d8F08E801E9EA1027C0CA2)
        ];

        strategy = address(0);

        maxLockTime = 365.25 days;

        name = "Staked VCX";
        symbol = "stVCX";

        // Actual deployment
        vault = new LockVault();

        vault.initialize(
            asset,
            rewardTokens,
            strategy,
            maxLockTime,
            name,
            symbol
        );

        vm.stopBroadcast();
    }
}
