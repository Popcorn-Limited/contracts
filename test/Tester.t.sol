// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test, console, console2} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ILBT} from "src/interfaces/external/lfj/ILBT.sol";
import {ILBRouter} from "src/interfaces/external/lfj/ILBRouter.sol";

struct CallStruct {
    address target;
    bytes4 data;
}

event LogBytes4(bytes4);
event LogBytes(bytes);

contract Tester is Test {
    function setUp() public {
        vm.createSelectFork("avalanche", 52057786);
    }

    function test__stuff() public {
        console.log(
            abi.encodeWithSelector(
                bytes4(keccak256("approve(address,uint256)")),
                address(0x18556DA13313f3532c54711497A8FedAC273220E),
                type(uint256).max
            )
        );
        console.log(
            abi.encodeWithSelector(
                bytes4(keccak256("approveForAll(address,bool)")),
                address(0x18556DA13313f3532c54711497A8FedAC273220E),
                true
            )
        );
    }
}
