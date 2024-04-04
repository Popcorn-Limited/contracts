// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {WeirollUtils, Command, InputIndex, OutputIndex, MockTarget, MockSender} from "../../../../src/vault/adapter/weiroll/WeirollUtils.sol";
import "forge-std/console.sol";

contract WeirollVMTest is Test {

    MockTarget mockTarget; 
    MockSender mockSender;
    WeirollUtils encoder;

    function setUp() public {
        encoder = new WeirollUtils();
        mockTarget = new MockTarget();
        mockSender = new MockSender();
    }

    function test_decode() public {
        // 0x70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D
        Command memory c = encoder.decodeCommand(hex"70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D");

        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(false, 255);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        OutputIndex memory output = OutputIndex(false,1);

        bytes32 comm = encoder.encodeCommand("balanceOf(address)", 2, inputs, output, address(0x79579633029a61963eDfbA1C0BE22498b6e0D33D));
        assertEq(comm, hex"70a082310200ffffffffff0179579633029a61963eDfbA1C0BE22498b6e0D33D");
    }

    function test_staticInput_staticOutput() public {
        // SIGNATURE 
        string memory signature = "staticInput_staticOutput(uint8,uint256)";
        
        // STATE
        bytes[] memory states = new bytes[](3);
        states[0] = abi.encode(10);
        states[1] = abi.encode(15);
        
        // INPUT VAR INDICES
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(false, 1);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        // OUTPUT VAR INDICES
        OutputIndex memory output = OutputIndex(false,2);

        // CALL TYPE 
        uint8 callType = 1; // 0 delegateCall, 1 call, 2 static call

        // TARGET 
        address target = address(mockTarget);

        // ENCODE COMMAND
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = encoder.encodeCommand(signature, callType, inputs, output, target);
        
        // SEND TX AND READ STATE
        bytes[] memory state = mockSender.executeMock(commands, states);

        // check the state has been written correctly by target 
        // with input data to make sure the call went through properly
        assertEq(abi.decode(state[2],(uint8)), 10);
    }

    function test_dynamicInput_staticOutput() public {
        // SIGNATURE 
        string memory signature = "dynamicInput_staticOutput(uint8[],uint256)";
        
        // STATE
        uint8[4] memory data = [0,1,2,3];
        bytes[] memory states = new bytes[](3);

        states[0] = abi.encodePacked(data.length, data);
        states[1] = abi.encode(15);
        
        // INPUT VAR INDICES
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(true, 0);
        inputs[1] = InputIndex(false, 1);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        // OUTPUT VAR INDICES
        OutputIndex memory output = OutputIndex(false,2);

        // CALL TYPE 
        uint8 callType = 1; // 0 delegateCall, 1 call, 2 static call

        // TARGET 
        address target = address(mockTarget);

        // ENCODE COMMAND
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = encoder.encodeCommand(signature, callType, inputs, output, target);
        
        // SEND TX AND READ STATE
        bytes[] memory state = mockSender.executeMock(commands, states);

        // check the state has been written correctly by target 
        // with input data to make sure the call went through properly
        assertEq(abi.decode(state[2], (uint8)), data[3]);
    }

    function test_mixedInput_bytesOutput() public {
        // SIGNATURE 
        string memory signature = "staticAndDynamicInput_bytesOutput(uint8[5],uint8[])";
        
        // STATE
        uint8[5] memory data = [0,1,2,3,4];
        bytes[] memory states = new bytes[](3);

        states[0] = abi.encode(data);
        states[1] = abi.encodePacked(data.length, data);
        
        // INPUT VAR INDICES
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(true, 1);
        inputs[2] = InputIndex(false, 255);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        // OUTPUT VAR INDICES
        OutputIndex memory output = OutputIndex(false,2);

        // CALL TYPE 
        uint8 callType = 1; // 0 delegateCall, 1 call, 2 static call

        // TARGET 
        address target = address(mockTarget);

        // ENCODE COMMAND
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = encoder.encodeCommand(signature, callType, inputs, output, target);
        
        // SEND TX AND READ STATE
        bytes[] memory state = mockSender.executeMock(commands, states);
        // check the state has been written correctly by target 
        // with input data to make sure the call went through properly
        assertEq(abi.decode(state[2], (uint8)), data[3]);
    }

    function test_multipleTypes() public {
        address bob = address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        // SIGNATURE 
        string memory signature = "multipleTypes(uint8[5],uint8[],address)";
        
        // STATE
        uint8[5] memory data = [0,1,2,3,4];
        bytes[] memory states = new bytes[](4);

        states[0] = abi.encode(data);
        states[1] = abi.encodePacked(data.length, data);
        states[2] = abi.encode(bob);

        // INPUT VAR INDICES
        InputIndex[6] memory inputs;
        inputs[0] = InputIndex(false, 0);
        inputs[1] = InputIndex(true, 1);
        inputs[2] = InputIndex(false, 2);
        inputs[3] = InputIndex(false, 255);
        inputs[4] = InputIndex(false, 255);
        inputs[5] = InputIndex(false, 255);

        // OUTPUT VAR INDICES
        OutputIndex memory output = OutputIndex(false,3);

        // CALL TYPE 
        uint8 callType = 1; // 0 delegateCall, 1 call, 2 static call, 3 value call, 14 update state call

        // TARGET 
        address target = address(mockTarget);

        // ENCODE COMMAND
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = encoder.encodeCommand(signature, callType, inputs, output, target);
        
        // SEND TX AND READ STATE
        bytes[] memory state = mockSender.executeMock(commands, states);
        // check the state has been written correctly by target 
        // with input data to make sure the call went through properly
        assertEq(abi.decode(state[3], (address)), bob);
    }

    function test_updateState() public {
        bytes[] memory states = new bytes[](3);

        states[0] = abi.encode(10);
        states[1] = abi.encode(7);

        // encode info to make states[0] an array
        uint8[] memory indices = new uint8[](2);
        indices[0] = 0;
        indices[1] = 1; 

        states[2] = abi.encode(indices, false, uint8(1));
        
        bytes32[] memory commands = new bytes32[](1);
        commands[0] = encoder.UPDATE_STATE_COMMAND();

        bytes[] memory state = mockSender.executeMock(commands, states);
        uint256[2] memory a= abi.decode(state[1], (uint256[2]));
        assertEq(a[0], 10);
        assertEq(a[1], 7);
    }

    // function test_exchange() public {
    //     // SIGNATURE 
    //     string memory signature = "exchange(address[3],uint256[5][2],uint256)";
        
    //     // STATE
    //     uint256[5][2] memory data;
    //     data[0] = [uint256(2), 10, 1, 1, 2];
        
    //     address[3] memory rewardRoute = [
    //         0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, // crv
    //         0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, // triCRV pool
    //         0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E // crvUSD
    //     ];

    //     bytes[] memory states = new bytes[](3);

    //     states[0] = abi.encode(rewardRoute);
    //     states[1] = abi.encode(data);
    //     states[2] = abi.encode(13);
        
    //     // INPUT VAR INDICES
    //     InputIndex[6] memory inputs;
    //     inputs[0] = InputIndex(false, 0);
    //     inputs[1] = InputIndex(false, 1);
    //     inputs[2] = InputIndex(false, 2);
    //     inputs[3] = InputIndex(false, 255);
    //     inputs[4] = InputIndex(false, 255);
    //     inputs[5] = InputIndex(false, 255);

    //     // OUTPUT VAR INDICES
    //     OutputIndex memory output = OutputIndex(false,0);

    //     // CALL TYPE 
    //     uint8 callType = 1; // 0 delegateCall, 1 call, 2 static call

    //     // TARGET 
    //     address target = address(mockTarget);

    //     // ENCODE COMMAND
    //     bytes32[] memory commands = new bytes32[](1);
    //     commands[0] = encoder.encodeCommand(signature, callType, inputs, output, target);
        
    //     // SEND TX AND READ STATE
    //     bytes[] memory state = mockSender.executeMock(commands, states);
    //     // check the state has been written correctly by target 
    //     // with input data to make sure the call went through properly
    //     assertEq(abi.decode(state[1], (uint256)), 13);
    // }

    function _encodeAndCall() internal {}

}