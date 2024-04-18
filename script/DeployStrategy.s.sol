// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {IBaseStrategy} from "../src/interfaces/IBaseStrategy.sol";
import {AuraCompounder} from "../src/strategies/aura/AuraCompounder.sol";

contract DeployStrategy is Script {
    address deployer;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address impl = new AuraCompounder();

        IBaseStrategy(impl).initialize(
            abi.encode(
                IERC20(0x625E92624Bc2D88619ACCc1788365A69767f6200),
                0x22f5413C075Ccd56D575A54763831C4c27A37Bdb,
                address(0),
                0,
                sigs,
                ""
            ),
            0xd061D61a4d941c39E5453435B6345Dc261C2fcE0,
            abi.encode(0xf69Fb60B79E463384b40dbFDFB633AB5a863C9A2)
        );

        vm.stopBroadcast();
    }
}
