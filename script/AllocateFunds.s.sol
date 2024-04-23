// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {MultiStrategyVault, IERC4626, IERC20, Allocation} from "../src/vaults/MultiStrategyVault.sol";

contract AllocateFunds is Script {
    Allocation[] internal allocations;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // allocations.push(Allocation({index:0,amount:20e18}));

        // MultiStrategyVault(0xcede40B40F7AF69f5Aa6b12D75fd5eA9cE138b93).pullFunds(allocations);

        // allocations.push(Allocation({index:1,amount:10e18}));
        // allocations.push(Allocation({index:2,amount:5e18}));
        // allocations.push(Allocation({index:3,amount:5e18}));

        // MultiStrategyVault(0xcede40B40F7AF69f5Aa6b12D75fd5eA9cE138b93).pushFunds(allocations);

        vm.stopBroadcast();
    }
}
