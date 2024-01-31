// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {FeeRecipientProxy, IERC20} from "../src/vault/FeeRecipientProxy.sol";

contract MoveFees is Script {
    address deployer;

    FeeRecipientProxy feeProxy =
        FeeRecipientProxy(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    event log_named_uint(string, uint256);

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        IERC20 token = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;

        //feeProxy.approveToken(tokens);

        token.transferFrom(
            address(feeProxy),
            address(0x5b86b57Afc1858D1A18320CFfc5286F6d1ac36c7),
            token.balanceOf(address(feeProxy))
        );

        emit log_named_uint("fee bal", token.balanceOf(address(feeProxy)));
        emit log_named_uint("deployer bal", token.balanceOf(address(deployer)));
        emit log_named_uint("recipient bal", token.balanceOf(address(0x5b86b57Afc1858D1A18320CFfc5286F6d1ac36c7)));

        vm.stopBroadcast();
    }
}
