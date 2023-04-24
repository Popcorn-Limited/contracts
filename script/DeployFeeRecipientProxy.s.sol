// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { Script } from "forge-std/Script.sol";
import { FeeRecipientProxy } from "../src/vault/FeeRecipientProxy.sol";

contract Deploy is Script {
  address deployer;

  function run() public {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPrivateKey);

    vm.startBroadcast(deployerPrivateKey);

    new FeeRecipientProxy{ salt: bytes32("FeeRecipientProxy") }(deployer);

    vm.stopBroadcast();
  }
}
