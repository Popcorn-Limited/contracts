// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ControllerModule, ISafe} from "src/peripheral/gnosis/ControllerModule.sol";

contract Tester is Test {
    address router = 0x48943F145686bF5c4580D545CDA405844D1f777b;
    address gauge = 0xc9aD14cefb29506534a973F7E0E97e68eCe4fa3f;
    address assetAddr = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address vaultAddr = 0xD3A17928245064B6DF5095a76e277fe441D538a4;

    IERC20 asset = IERC20(assetAddr);
    IERC4626 vault = IERC4626(vaultAddr);

    address alice = address(0xABCD);
    address bob = address(0xDCBA);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
    }

    function testA() public {
        address[] memory newOwners = new address[](3);
        newOwners[0] = 0x2C3B135cd7dc6C673b358BEF214843DAb3464278;
        newOwners[1] = 0x22f5413C075Ccd56D575A54763831C4c27A37Bdb;
        newOwners[2] = 0x3cD3dD1F7F96E9ADa9738e688d8997BDfE90D48D;

        vm.prank(0x2C3B135cd7dc6C673b358BEF214843DAb3464278);
        ControllerModule(0xDFbd231A7229Ca8475FCE477e225e72c0c27B201)
            .overtakeSafe(newOwners, 2);

        address[] memory owners = ISafe(
            0x3C99dEa58119DE3962253aea656e61E5fBE21613
        ).getOwners();

        console.log(owners[0]);
        console.log(owners[1]);
        console.log(owners[2]);

        uint256 threshold = ISafe(0x3C99dEa58119DE3962253aea656e61E5fBE21613)
            .getThreshold();

        console.log(threshold);
    }
}
