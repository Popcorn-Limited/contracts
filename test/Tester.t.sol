// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";
import {ILBRouter} from "src/interfaces/external/lfj/ILBRouter.sol";
import {BaseAaveLeverageStrategy} from "src/strategies/BaseAaveLeverageStrategy.sol";

struct CallStruct {
    address target;
    bytes4 data;
}

event LogBytes4(bytes4);
event LogBytes(bytes);

contract Tester is Test {
    function setUp() public {
        vm.createSelectFork("polygon", 63342440);
    }

    function test__stuff() public {
        console2.log(
            BaseAaveLeverageStrategy(payable(0x40B74aC60F4133b31F297767B455B4328d917809))
                .maxLTV()
        );
        console2.log(
            BaseAaveLeverageStrategy(payable(0x40B74aC60F4133b31F297767B455B4328d917809))
                .targetLTV()
        );
    }
}
