// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

struct CallStruct {
    address target;
    bytes4 data;
}

event LogBytes4(bytes4);
event LogBytes(bytes);

contract Tester is Test {
    CallStruct[] public callStructs;
    function setUp() public {}

    function test__stuff() public {
        callStructs.push(CallStruct({target: address(this), data: bytes4("")}));
    }
}
