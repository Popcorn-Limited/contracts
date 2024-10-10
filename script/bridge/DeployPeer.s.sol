// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../../src/bridge/PeerToken.sol";

contract DeployPeer is Script {
    function setUp() public {}

    function run() public {
        address minter = msg.sender;
        address owner = msg.sender;
        
        vm.startBroadcast();

        PeerToken t = new PeerToken();

        t.initalize(minter, owner, "Wormhole Bridged VCX", "wVCX");

        vm.stopBroadcast();
    }
}

contract SetMinter is Script {
    function setUp() public {}

    // to set a new ntt manager as peer token minter
    function run() public {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address ntt_manager = address(0x67eB307120D219d84d1a66a62016D396045F352b); // edit
        PeerToken t = PeerToken(0xe15323Ae15269782fAdeF9937D24f675bdDdbC35); // edit
        
        vm.startBroadcast();

        t.setMinter(ntt_manager);
        vm.stopBroadcast();
    }
}