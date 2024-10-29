// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";
import {ILBRouter} from "src/interfaces/external/lfj/ILBRouter.sol";
import {BaseAaveLeverageStrategy} from "src/strategies/BaseAaveLeverageStrategy.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

struct CallStruct {
    address target;
    bytes4 data;
}

event LogBytes4(bytes4);
event LogBytes(bytes);

contract Tester is Test {
    using FixedPointMathLib for uint256;


    function setUp() public {
        //vm.createSelectFork("polygon", 63342440);
    }

    function test__stuff() public {
       uint256 x = 100e18;
       uint256 y = 100e18;
       uint256 z = 100e18;
       console2.log(x.mulDivUp(y, z));
    }
}
