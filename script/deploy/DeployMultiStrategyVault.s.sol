// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MultiStrategyVault, IERC4626, IERC20} from "../../src/vaults/MultiStrategyVault.sol";

contract DeployMultiStrategyVault is Script {
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
        asset = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

        strategies = [
            IERC4626(0x658a94eF990c5307707a428C927ADcB65B89BD8F),
            IERC4626(0x1C9432248C5437C52A6cdff701259c247f870f88)
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
