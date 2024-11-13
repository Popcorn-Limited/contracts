// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ParamsGuard, ParamRule} from "src/peripheral/gnosis/transactionGuard/ParamsGuard.sol";
import "forge-std/console.sol";

contract ParamsGuardTest is Test {
    ParamsGuard public guard;
    address public user = address(0x1);

    function setUp() public {
        guard = new ParamsGuard();
    }

    function test_dynamicVar() public {
        // function d(uint256,uint256,bytes,uint256)
        // expected value at position 0 is 2
        ParamRule memory rule = ParamRule(true, 2, false, 0, hex"deadbeefcafebe");

        bytes4 selector = bytes4(keccak256(bytes("d(uint256,uint256,bytes,uint256)")));
        guard.setRule(selector, rule);

        bytes memory txCalldata = abi.encodeWithSelector(selector, 1,2,hex"deadbeefcafebe",3);
        console.logBytes(txCalldata);

        bytes memory data = guard.verifyTxData(txCalldata);
        console.logBytes(data);
        assertEq(data, hex"deadbeefcafebe");
    }

    function test_dynamicVar_recursive() public {
        // function d(uint256,uint256,bytes,uint256)
        // bytes are abi.encode(uint256,address,uint256)

        bytes memory data = abi.encode(1,address(0x1234),2);

        ParamRule memory rule = ParamRule(true, 2, true, 1, abi.encode(address(0x1234)));

        bytes4 selector = bytes4(keccak256(bytes("d(uint256,uint256,bytes,uint256)")));
        guard.setRule(selector, rule);

        bytes memory txCalldata = abi.encodeWithSelector(selector, 1,2,data,3);
        console.logBytes(txCalldata);

        bytes memory actualData = guard.verifyTxData(txCalldata);
        console.logBytes(actualData);
        assertEq(actualData, abi.encode(address(0x1234)));
    }
}