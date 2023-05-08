// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

interface IAuroraStNear {
    function wNear() external view returns (address);

    function stNearPrice() external view returns (uint256);
}

contract Tester is Test {
    IAuroraStNear auroraStNear =
        IAuroraStNear(0x534BACf1126f60EA513F796a3377ff432BE62cf9);

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("aurora"));
        vm.selectFork(forkId);
    }

    function test_stuff() public {
        emit log_address(auroraStNear.wNear());
        emit log_uint(auroraStNear.stNearPrice());
    }
}
