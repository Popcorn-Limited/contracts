// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";

struct CallStruct {
    address target;
    bytes4 data;
}

event LogBytes4(bytes4);
event LogBytes(bytes);

contract Tester is Test {
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"));
    }

    function test__stuff() public {
        ILBT(0xEA7309636E7025Fda0Ee2282733Ea248c3898495).getBin(8386853);
    }
}
