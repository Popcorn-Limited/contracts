// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {MultiStrategyVault, IERC4626, IERC20} from "../../src/vaults/MultiStrategyVault.sol";

contract DeployMultiStrategyVault is Script {
    address deployer;

    IERC20 internal asset;
    IERC4626[] internal strategies;
    uint256 internal defaultDepositIndex;
    uint256[] internal withdrawalQueue;
    uint256 internal depositLimit;
    address internal owner;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // @dev edit this values below
        asset = IERC20(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);

        strategies = [
            IERC4626(0x61dCd1Da725c0Cdb2C6e67a0058E317cA819Cf5f),
            IERC4626(0x9168AC3a83A31bd85c93F4429a84c05db2CaEF08),
            IERC4626(0x2D0483FefAbA4325c7521539a3DFaCf94A19C472),
            IERC4626(0x6076ebDFE17555ed3E6869CF9C373Bbd9aD55d38)
        ];

        defaultDepositIndex = uint256(0);

        withdrawalQueue = [0, 1, 2, 3];

        depositLimit = type(uint256).max;

        owner = deployer;

        // Actual deployment
        MultiStrategyVault vault = new MultiStrategyVault();

        vault.initialize(asset, strategies, defaultDepositIndex, withdrawalQueue, depositLimit, deployer);

        vm.stopBroadcast();
    }
}
