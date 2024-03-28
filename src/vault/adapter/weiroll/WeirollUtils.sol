// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {VM} from "./VM.sol";

struct Command {
    bytes4 sig; // function signature
    uint8 callType; // 0: delegate call, 1: call, 2: static call
    uint8[6] inputIndexes; // indexes in the state array where input variables are taken from 
    uint8 outputIndex; // index in the state array where output is written
    address target; // target contract 
}

struct InputIndex {
    bool isDynamicArray;
    uint8 index;
}

struct OutputIndex {
    bool isDynamicOutput;
    uint8 index;
}

contract WeirollUtils {
    function decodeCommand(bytes calldata command) public pure returns (Command memory c) {
        c.sig = bytes4(command[0:4]);
        c.callType = uint8(bytes1(command[4:5]));
        c.inputIndexes[0] = uint8(bytes1(command[5:6]));
        c.inputIndexes[1] = uint8(bytes1(command[6:7]));
        c.inputIndexes[2] = uint8(bytes1(command[7:8]));
        c.inputIndexes[3] = uint8(bytes1(command[8:9]));
        c.inputIndexes[4] = uint8(bytes1(command[9:10]));
        c.inputIndexes[5] = uint8(bytes1(command[10:11]));
        c.outputIndex = uint8(bytes1(command[11:12]));
        c.target = address(bytes20(command[12:32]));
    }
    
    function encodeCommand(
        string memory functionSig, 
        uint8 callType, 
        InputIndex[6] memory inputIndexes, 
        OutputIndex memory outputIndex, 
        address target
    ) public pure returns (bytes32 command) {
       bytes memory inputIn;

        for(uint i=0; i<6; i++){
            InputIndex memory index = inputIndexes[i];
            uint256 ind = index.index;

            if(!index.isDynamicArray){
                inputIn = abi.encodePacked(
                    inputIn, 
                    bytes1(bytes32(abi.encode(ind)) << 31*8)
                );
            } else {
                uint256 actualNumb;
                if(ind == 255) {
                    actualNumb = ind;
                } else {
                    // append 1 to the MSB cause it's dynamic input
                    actualNumb = 2**7 + ind;
                }
                inputIn = abi.encodePacked(
                    inputIn, 
                    bytes1(bytes32(abi.encode(actualNumb)) << 31*8)
                );
            }
        }

        uint256 out = outputIndex.index;
        if(outputIndex.isDynamicOutput) {
            out += 2**6; // append 1 to MSB
        }

       command = bytes32(abi.encodePacked(
            bytes4(keccak256(abi.encodePacked(functionSig))),
            bytes1(callType),
            inputIn,
            bytes1(bytes32(abi.encode(out)) << 31*8),
            bytes20(target))
        );
    }
}

contract MockSender is VM {
    function executeMock(bytes32[] memory c, bytes[] memory s) public returns (bytes[] memory state) {
        state = _execute(c, s);
    }
}

contract MockTarget {
    function staticInput_staticOutput(uint8 a, uint256 b) public pure returns (uint8) {
        return a;
    }

    function dynamicInput_staticOutput(
        uint8[] memory a, 
        uint256 b
    ) public returns (uint8) {
        return a[a.length - 1];
    }

    function staticAndDynamicInput_bytesOutput(uint8[5] memory a, uint8[] memory b) public pure returns (uint8) {
        return b[b.length - 2];
    }

    function multipleTypes(uint8[5] memory a, uint8[] memory b, address c) public pure returns (address){
        return c;
    }

    fallback() external{
    }
}