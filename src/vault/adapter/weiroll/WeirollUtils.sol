// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {VM} from "./VM.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

struct Command {
    bytes4 sig; // function signature
    uint8 callType; // 0: delegate call, 1: call, 2: static call
    uint8[6] inputIndexes; // indexes in the state array where input variables are taken from 
    uint8 outputIndex; // index in the state array where output is written
    address target; // target contract 
}

struct JsonCommand {
    uint256 commandType; // 0 delegateCall, 1 call, 2 static call, 3 call with value
    string signature;
    address target;
}

struct InputIndex {
    bool isDynamicArray;
    uint8 index;
}

struct OutputIndex {
    bool isDynamicOutput;
    uint8 index;
}

library WeirollBuilder {
    using stdJson for string;
    using Strings for uint256;

    function getCommandAndStateLength(string memory json, string memory key) internal returns (uint256 commLen, uint256 stateLen) {
        commLen = json.readUint(
            string.concat(".", key, ".numCommands")
        );

        stateLen = json.readUint(
            string.concat(".", key, ".stateLen")
        );
    }

    function getCommandsAndState(string memory json, string memory key) internal returns (bytes32[] memory comm, bytes[] memory states){
        comm = getCommandsFromJson(json, key);
        states = encodeCommandState(json, key);
    }

    function getCommandsFromJson(string memory json, string memory key) internal returns (bytes32[] memory comms) {
        uint256 numCommands = json.readUint(string.concat(".", key, ".numCommands"));

        comms = new bytes32[](numCommands);

        for(uint256 i=0; i<numCommands; i++) {
            string memory k = string.concat(".", key, ".commands[", i.toString(), "].");

            JsonCommand memory command = abi.decode(
                json.parseRaw(string.concat(k, "command")),
                (JsonCommand)
            );

            if(command.commandType == 14) {
                comms[i] = hex"00000000200000000000000000000000000000000000000000000000000000";
            } else {
                InputIndex[6] memory inputs = getCommandInputs(json, k);
                OutputIndex memory output = getCommandOutput(json, k);

                comms[i] = encodeCommand(command.signature, uint8(command.commandType), inputs, output, command.target);
            }
        }
    }

    function encodeCommandState(string memory json, string memory key) internal returns (bytes[] memory states) {
        uint256 len = json.readUint(string.concat(".", key, ".stateLen"));
        states = new bytes[](len);

        for(uint256 i=0; i<len; i++) {
            string memory t = json.readString(string.concat(".", key, ".state[", i.toString(), "].type"));

            bytes32 ty = keccak256(abi.encode(t));

            string memory valueKey = string.concat(".", key, ".state[", i.toString(), "].value");

            if(ty == keccak256(abi.encode("bytes"))) {
                // bytes memory v = json.readBytes(valueKey);
                states[i] = json.readBytes(valueKey);

                // if(keccak256(v) == keccak256(hex"")) {
                //     states[i] = abi.encode(address(adapter));
                // } else {
                //     states[i] = v;
                // }


            } else if (ty == keccak256(abi.encode("uint"))) {
                uint256 v = json.readUint(valueKey);
                states[i] = abi.encode(v);
            } else if (ty == keccak256(abi.encode("uint[][]"))) {
                uint256 numRows = json.readUint(string.concat(".", key, ".state[", i.toString(), "].numRows"));

                for(uint256 j=0; j<numRows; j++) {
                    // .value[j]
                    string memory rowKey = string.concat(valueKey, "[", j.toString(), "]");
                    uint256[] memory rowValue = json.readUintArray(rowKey);
                    // concat encoded rows
                    states[i] = abi.encodePacked(states[i], rowValue);
                }   
            } else if (ty == keccak256(abi.encode("bool"))) {
                bool v = json.readBool(valueKey);
                states[i] = abi.encode(v);
            } else if (ty == keccak256(abi.encode("address"))) {
                address v = json.readAddress(valueKey);
                states[i] = abi.encode(v);
            } else if (ty == keccak256(abi.encode("address[]"))) {
                address[] memory v = json.readAddressArray(valueKey);
                bool isFixedSize = json.readBool(string.concat(".", key, ".state[", i.toString(), "].fixedSize"));
                
                // encode either as dynamic array or as fixed size
                states[i] = isFixedSize ? abi.encodePacked(v) : abi.encode(v);
            }
        }
    }

    function getCommandInputs(string memory json, string memory key) internal returns (InputIndex[6] memory inputs) {
        for (uint256 i=0; i<6; i++) {
            bool isDynamic = json.readBool(
                string.concat(key, "inputIds[", i.toString(), "].isDynamicArray")
            );

            uint256 ind = json.readUint(
                string.concat(key, "inputIds[", i.toString(), "].index")
            );

            inputs[i] = InputIndex(isDynamic, uint8(ind));
        }
    }

    function getCommandOutput(string memory json, string memory key) internal returns (OutputIndex memory output) {
        bool isDynamic = json.readBool(string.concat(key, "outputId.isDynamicOutput"));
        uint256 ind = json.readUint(string.concat(key, "outputId.index"));

        output = OutputIndex(isDynamic, uint8(ind));
    }

    function encodeCommand(
        string memory functionSig, 
        uint8 callType, 
        InputIndex[6] memory inputIndexes, 
        OutputIndex memory outputIndex, 
        address target
    ) internal pure returns (bytes32 command) {
       bytes memory inputIn;

       if(callType == 14) {
        // command is to update state
        return hex"00000000200000000000000000000000000000000000000000000000000000";
       }

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

    function decodeCommand(bytes calldata command) internal pure returns (Command memory c) {
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
}

contract WeirollUtils {
    bytes32 public constant UPDATE_STATE_COMMAND = hex"00000000200000000000000000000000000000000000000000000000000000";
    
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

       if(callType == 14) {
        // command is to update state
        return UPDATE_STATE_COMMAND;
       }

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