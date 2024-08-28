// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MultiStrategyVault, IERC4626, IERC20} from "src/vaults/MultiStrategyVault.sol";

contract Deploy is Script {
    IERC20 internal asset;
    IERC4626[] internal strategies;
    uint256 internal defaultDepositIndex;
    uint256[] internal withdrawalQueue;
    uint256 internal depositLimit;
    address internal owner;

    function run() public returns (MultiStrategyVault vault) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // @dev edit this values below
        asset = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

        strategies = [
            IERC4626(0xF82316c0cd110dB4c4a6c15F85dFaD7266551854),
            IERC4626(0x377DFCC7B9ce9aDD96347f34b2303C9bD8067e01)
        ];

        defaultDepositIndex = uint256(0);

        withdrawalQueue = [0, 1];

        depositLimit = type(uint256).max;

        owner = msg.sender;

        // Actual deployment
        vault = new MultiStrategyVault();

        vault.initialize(
            asset,
            strategies,
            defaultDepositIndex,
            withdrawalQueue,
            depositLimit,
            owner
        );

        vm.stopBroadcast();
    }
}
