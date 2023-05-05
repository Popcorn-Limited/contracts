// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Test} from "forge-std/Test.sol";

contract Delegator {
    function asset() public view returns (address) {
        return address(0x5555);
    }

    function delegate(address delegatee) public {
        address(delegatee).delegatecall(abi.encodeWithSignature("doWork()"));
    }
}

contract Delegate {
    function doWork() public returns (address) {
        address asset = Delegator(address(this)).asset();
        return asset;
    }
}

contract Tester is Test {
    Delegator delegator;
    Delegate delegate;

    function setUp() public {
        delegator = new Delegator();
        delegate = new Delegate();
    }

    function test_smth() public {
        delegator.delegate(address(delegate));
    }
}
