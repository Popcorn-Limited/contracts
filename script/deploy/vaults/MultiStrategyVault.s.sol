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

    uint256 performanceFee;
    uint256 managementFee;

    function run() public returns (MultiStrategyVault vault) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // @dev edit this values below
        asset = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

        strategies = [
            IERC4626(0x430cF36a989DFef9ff8F0f3b7738059715a07B6c),
            IERC4626(0x5769F1c62Fa2AA6087df3dd1FA6a7Ae89Bb45FFd),
            IERC4626(0x7D375fAA1A42F183ACe063e188c3c95fCBf04e93),
            IERC4626(0xA2655b902dc8e6AfAD89e03f13fc2a484043F416),
            IERC4626(0x970550f7057fdE945a7Ca3B32EBc23994ABC2239),
            IERC4626(0xA714B8585f5a17ae4E85700fA3d81d0ab0C6dDEB),
            IERC4626(0xCEe8104ED8796CD6eF6d7CC761Ea88FaFD3b80ee),
            IERC4626(0x7385AaFE2FD203B2720f172178dBCf1951CcC062),
            IERC4626(0xb8108710706a6B870e06270c3a2e6570aE03804a),
            IERC4626(0x15f8190294846c429615435Bd1A3E1Efe0dc93Ee)
        ];

        defaultDepositIndex = uint256(0);

        withdrawalQueue = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

        depositLimit = type(uint256).max;

        owner = msg.sender;

        performanceFee = 1e17; // 10%
        managementFee = 2e16; // 2%

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

        vault.setFees(
            performanceFee,
            managementFee
        );

        vm.stopBroadcast();
    }
}
