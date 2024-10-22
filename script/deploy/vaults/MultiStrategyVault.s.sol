// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MultiStrategyVault, InitializeParams, IERC4626, IERC20} from "src/vaults/MultiStrategyVault.sol";

contract Deploy is Script {
    IERC20 internal asset;
    IERC4626[] internal strategies;
    uint256 internal defaultDepositIndex;
    uint256[] internal withdrawalQueue;
    uint256 internal depositLimit;
    address internal owner;
    address internal feeRecipient;
    uint256 performanceFee;
    uint256 managementFee;

    function run() public returns (MultiStrategyVault vault) {
        vm.startBroadcast();
        console.log("msg.sender:", msg.sender);

        // @dev edit this values below
        asset = IERC20(0xFc00000000000000000000000000000000000001);

        strategies = [
            IERC4626(0x8EdA613EC96992D3C42BCd9aC2Ae58a92929Ceb2),
            IERC4626(0x4F968317721B9c300afBff3FD37365637318271D)
        ];

        defaultDepositIndex = uint256(0);

        withdrawalQueue = [0, 1];

        depositLimit = type(uint256).max;

        owner = msg.sender;

        feeRecipient = address(0xe3Bf0045C12C1CF31D7DAc40D0Fc0a49a410bBA2);

        performanceFee = 0; // 10%
        managementFee = 1e16; // 2%

        // Actual deployment
        vault = new MultiStrategyVault();

        vault.initialize(
            InitializeParams(
                asset,
                strategies,
                defaultDepositIndex,
                withdrawalQueue,
                depositLimit,
                owner,
                feeRecipient
            )
        );

        vault.setFees(performanceFee, managementFee);

        vm.stopBroadcast();
    }
}
