// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ControllerModule, ISafe} from "src/peripheral/gnosis/controllerModule/MainControllerModule.sol";

interface ILooper {
    function adjustLeverage() external;
}

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
        vm.createSelectFork(vm.rpcUrl("mainnet"));
    }

    function testA() public {
        ILooper(0xcdc20718Cc869c6DBD541B7302C97758fF17250b).adjustLeverage();
    }
}
