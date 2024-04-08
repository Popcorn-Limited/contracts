// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.16;

library CommandBuilder {
    uint256 constant IDX_VARIABLE_LENGTH = 0x80;
    uint256 constant IDX_VALUE_MASK = 0x7f;
    uint256 constant IDX_END_OF_ARGS = 0xff;
    uint256 constant IDX_USE_STATE = 0xfe;
    uint256 constant IDX_ARRAY_START = 0xfd;
    uint256 constant IDX_TUPLE_START = 0xfc;
    uint256 constant IDX_DYNAMIC_END = 0xfb;

    function buildInputs(
        bytes[] memory state,
        bytes4 selector,
        bytes32 indices,
        uint256 indicesLength
    ) internal view returns (bytes memory ret) {
        uint256 idx; // The current command index
        uint256 offsetIdx; // The index of the current free offset

        uint256 count; // Number of bytes in whole ABI encoded message
        uint256 free; // Pointer to first free byte in tail part of message
        uint256[] memory dynamicLengths = new uint256[](10); // Optionally store the length of all dynamic types (a command cannot fit more than 10 dynamic types)

        bytes memory stateData; // Optionally encode the current state if the call requires it

        // Determine the length of the encoded data
        for (uint256 i; i < indicesLength; ) {
            idx = uint8(indices[i]);
            if (idx == IDX_END_OF_ARGS) {
                indicesLength = i;
                break;
            }
            if (idx & IDX_VARIABLE_LENGTH != 0) {
                if (idx == IDX_USE_STATE) {
                    if (stateData.length == 0) {
                        stateData = abi.encode(state);
                    }
                    unchecked {
                        count += stateData.length;
                    }
                } else {
                    (dynamicLengths, offsetIdx, count, i) = setupDynamicType(
                        state,
                        indices,
                        dynamicLengths,
                        idx,
                        offsetIdx,
                        count,
                        i
                    );
                }
            } else {
                count = setupStaticVariable(state, count, idx);
            }
            unchecked {
                free += 32;
                ++i;
            }
        }

        // Encode it
        ret = new bytes(count + 4);
        assembly {
            mstore(add(ret, 32), selector)
        }
        offsetIdx = 0;
        // Use count to track current memory slot
        assembly {
            count := add(ret, 36)
        }
        for (uint256 i; i < indicesLength; ) {
            idx = uint8(indices[i]);
            if (idx & IDX_VARIABLE_LENGTH != 0) {
                if (idx == IDX_USE_STATE) {
                    assembly {
                        mstore(count, free)
                    }
                    memcpy(stateData, 32, ret, free + 4, stateData.length - 32);
                    unchecked {
                        free += stateData.length - 32;
                    }
                } else if (idx == IDX_ARRAY_START) {
                    // Start of dynamic type, put pointer in current slot
                    assembly {
                        mstore(count, free)
                    }
                    (offsetIdx, free, i, ) = encodeDynamicArray(
                        ret,
                        state,
                        indices,
                        dynamicLengths,
                        offsetIdx,
                        free,
                        i
                    );
                } else if (idx == IDX_TUPLE_START) {
                    // Start of dynamic type, put pointer in current slot
                    assembly {
                        mstore(count, free)
                    }
                    (offsetIdx, free, i, ) = encodeDynamicTuple(
                        ret,
                        state,
                        indices,
                        dynamicLengths,
                        offsetIdx,
                        free,
                        i
                    );
                } else {
                    // Variable length data
                    uint256 argLen = state[idx & IDX_VALUE_MASK].length;
                    // Put a pointer in the current slot and write the data to first free slot
                    assembly {
                        mstore(count, free)
                    }
                    memcpy(
                        state[idx & IDX_VALUE_MASK],
                        0,
                        ret,
                        free + 4,
                        argLen
                    );
                    unchecked {
                        free += argLen;
                    }
                }
            } else {
                // Fixed length data (length previously checked to be 32 bytes)
                bytes memory stateVar = state[idx & IDX_VALUE_MASK];
                // Write the data to current slot
                assembly {
                    mstore(count, mload(add(stateVar, 32)))
                }
            }
            unchecked {
                count += 32;
                ++i;
            }
        }
    }

    function setupStaticVariable(
        bytes[] memory state,
        uint256 count,
        uint256 idx
    ) internal pure returns (uint256 newCount) {
        require(
            state[idx & IDX_VALUE_MASK].length == 32,
            "Static state variables must be 32 bytes"
        );
        unchecked {
            newCount = count + 32;
        }
    }
    
    // encode params from different state slots in array format in a single state slot
    function elementsToArray(bytes[] memory state) internal pure returns (bytes[] memory) {        
        (
            uint8[] memory indexes, 
            bool isDynamic, 
            uint8 outputIndex
        ) = abi.decode(state[(state.length - 1) & IDX_VALUE_MASK], (uint8[], bool, uint8));

        bytes memory arrayElement;
        bytes32[] memory elements = new bytes32[](indexes.length);

        for(uint i=0; i<indexes.length; i++) {
            elements[i] = bytes32(state[uint256(indexes[i])]);
        }

        if(isDynamic) {
            // dynamic array
            arrayElement = abi.encodePacked(elements.length, elements);
        } else {
            // fixed size array
            arrayElement = abi.encodePacked(elements);
        }

        // write to state
        state[uint256(outputIndex)] = arrayElement;
        
        return state;
    }
    function setupDynamicVariable(
        bytes[] memory state,
        uint256 count,
        uint256 idx
    ) internal pure returns (uint256 newCount) {
        bytes memory arg = state[idx & IDX_VALUE_MASK];
        // Validate the length of the data in state is a multiple of 32
        uint256 argLen = arg.length;
        require(
            argLen != 0 && argLen % 32 == 0,
            "Dynamic state variables must be a multiple of 32 bytes"
        );
        // Add the length of the value, rounded up to the next word boundary, plus space for pointer
        unchecked {
            newCount = count + argLen + 32;
        }
    }

    function setupDynamicType(
        bytes[] memory state,
        bytes32 indices,
        uint256[] memory dynamicLengths,
        uint256 idx,
        uint256 offsetIdx,
        uint256 count,
        uint256 index
    ) internal view returns (
        uint256[] memory newDynamicLengths,
        uint256 newOffsetIdx,
        uint256 newCount,
        uint256 newIndex
    ) {
        if (idx == IDX_ARRAY_START) {
            (newDynamicLengths, newOffsetIdx, newCount, newIndex) = setupDynamicArray(
                state,
                indices,
                dynamicLengths,
                offsetIdx,
                count,
                index
            );
        } else if (idx == IDX_TUPLE_START) {
            (newDynamicLengths, newOffsetIdx, newCount, newIndex) = setupDynamicTuple(
                state,
                indices,
                dynamicLengths,
                offsetIdx,
                count,
                index
            );
        } else {
            newDynamicLengths = dynamicLengths;
            newOffsetIdx = offsetIdx;
            newIndex = index;
            newCount = setupDynamicVariable(state, count, idx);
        }
    }

    function setupDynamicArray(
        bytes[] memory state,
        bytes32 indices,
        uint256[] memory dynamicLengths,
        uint256 offsetIdx,
        uint256 count,
        uint256 index
    ) internal view returns (
        uint256[] memory newDynamicLengths,
        uint256 newOffsetIdx,
        uint256 newCount,
        uint256 newIndex
    ) {
        // Current idx is IDX_ARRAY_START, next idx will contain the array length
        unchecked {
            newIndex = index + 1;
            newCount = count + 32;
        }
        uint256 idx = uint8(indices[newIndex]);
        require(
            state[idx & IDX_VALUE_MASK].length == 32,
            "Array length must be 32 bytes"
        );
        (newDynamicLengths, newOffsetIdx, newCount, newIndex) = setupDynamicTuple(
            state,
            indices,
            dynamicLengths,
            offsetIdx,
            newCount,
            newIndex
        );
    }

    function setupDynamicTuple(
        bytes[] memory state,
        bytes32 indices,
        uint256[] memory dynamicLengths,
        uint256 offsetIdx,
        uint256 count,
        uint256 index
    ) internal view returns (
        uint256[] memory newDynamicLengths,
        uint256 newOffsetIdx,
        uint256 newCount,
        uint256 newIndex
    ) {
        uint256 idx;
        uint256 offset;
        newDynamicLengths = dynamicLengths;
        // Progress to first index of the data and progress the next offset idx
        unchecked {
            newIndex = index + 1;
            newOffsetIdx = offsetIdx + 1;
            newCount = count + 32;
        }
        while (newIndex < 32) {
            idx = uint8(indices[newIndex]);
            if (idx & IDX_VARIABLE_LENGTH != 0) {
                if (idx == IDX_DYNAMIC_END) {
                    newDynamicLengths[offsetIdx] = offset;
                    // explicit return saves gas ¯\_(ツ)_/¯
                    return (newDynamicLengths, newOffsetIdx, newCount, newIndex);
                } else {
                    require(idx != IDX_USE_STATE, "Cannot use state from inside dynamic type");
                    (newDynamicLengths, newOffsetIdx, newCount, newIndex) = setupDynamicType(
                        state,
                        indices,
                        newDynamicLengths,
                        idx,
                        newOffsetIdx,
                        newCount,
                        newIndex
                    );
                }
            } else {
                newCount = setupStaticVariable(state, newCount, idx);
            }
            unchecked {
                offset += 32;
                ++newIndex;
            }
        }
        revert("Dynamic type was not properly closed");
    }

    function encodeDynamicArray(
        bytes memory ret,
        bytes[] memory state,
        bytes32 indices,
        uint256[] memory dynamicLengths,
        uint256 offsetIdx,
        uint256 currentSlot,
        uint256 index
    ) internal view returns (
        uint256 newOffsetIdx,
        uint256 newSlot,
        uint256 newIndex,
        uint256 length
    ) {
        // Progress to array length metadata
        unchecked {
            newIndex = index + 1;
            newSlot = currentSlot + 32;
        }
        // Encode array length
        uint256 idx = uint8(indices[newIndex]);
        // Array length value previously checked to be 32 bytes
        bytes memory stateVar = state[idx & IDX_VALUE_MASK];
        assembly {
            mstore(add(add(ret, 36), currentSlot), mload(add(stateVar, 32)))
        }
        (newOffsetIdx, newSlot, newIndex, length) = encodeDynamicTuple(
            ret,
            state,
            indices,
            dynamicLengths,
            offsetIdx,
            newSlot,
            newIndex
        );
        unchecked {
            length += 32; // Increase length to account for array length metadata
        }
    }

    function encodeDynamicTuple(
        bytes memory ret,
        bytes[] memory state,
        bytes32 indices,
        uint256[] memory dynamicLengths,
        uint256 offsetIdx,
        uint256 currentSlot,
        uint256 index
    ) internal view returns (
        uint256 newOffsetIdx,
        uint256 newSlot,
        uint256 newIndex,
        uint256 length
    ) {
        uint256 idx;
        uint256 argLen;
        uint256 freePointer = dynamicLengths[offsetIdx]; // The pointer to the next free slot
        unchecked {
            newSlot = currentSlot + freePointer; // Update the next slot
            newOffsetIdx = offsetIdx + 1; // Progress to next offsetIdx
            newIndex = index + 1; // Progress to first index of the data
        }
        // Shift currentSlot to correct location in memory
        assembly {
            currentSlot := add(add(ret, 36), currentSlot)
        }
        while (newIndex < 32) {
            idx = uint8(indices[newIndex]);
            if (idx & IDX_VARIABLE_LENGTH != 0) {
                if (idx == IDX_DYNAMIC_END) {
                    break;
                } else if (idx == IDX_ARRAY_START) {
                    // Start of dynamic type, put pointer in current slot
                    assembly {
                        mstore(currentSlot, freePointer)
                    }
                    (newOffsetIdx, newSlot, newIndex, argLen) = encodeDynamicArray(
                        ret,
                        state,
                        indices,
                        dynamicLengths,
                        newOffsetIdx,
                        newSlot,
                        newIndex
                    );
                    unchecked {
                        freePointer += argLen;
                        length += (argLen + 32); // data + pointer
                    }
                } else if (idx == IDX_TUPLE_START) {
                    // Start of dynamic type, put pointer in current slot
                    assembly {
                        mstore(currentSlot, freePointer)
                    }
                    (newOffsetIdx, newSlot, newIndex, argLen) = encodeDynamicTuple(
                        ret,
                        state,
                        indices,
                        dynamicLengths,
                        newOffsetIdx,
                        newSlot,
                        newIndex
                    );
                    unchecked {
                        freePointer += argLen;
                        length += (argLen + 32); // data + pointer
                    }
                } else  {
                    // Variable length data
                    argLen = state[idx & IDX_VALUE_MASK].length;
                    // Start of dynamic type, put pointer in current slot
                    assembly {
                        mstore(currentSlot, freePointer)
                    }
                    memcpy(
                        state[idx & IDX_VALUE_MASK],
                        0,
                        ret,
                        newSlot + 4,
                        argLen
                    );
                    unchecked {
                        newSlot += argLen;
                        freePointer += argLen;
                        length += (argLen + 32); // data + pointer
                    }
                }
            } else {
                // Fixed length data (length previously checked to be 32 bytes)
                bytes memory stateVar = state[idx & IDX_VALUE_MASK];
                // Write to first free slot
                assembly {
                    mstore(currentSlot, mload(add(stateVar, 32)))
                }
                unchecked {
                    length += 32;
                }
            }
            unchecked {
                currentSlot += 32;
                ++newIndex;
            }
        }
    }

    function writeOutputs(
        bytes[] memory state,
        bytes1 index,
        bytes memory output
    ) internal pure returns (bytes[] memory) {
        uint256 idx = uint8(index);
        if (idx == IDX_END_OF_ARGS) return state;

        if (idx & IDX_VARIABLE_LENGTH != 0) {
            if (idx == IDX_USE_STATE) {
                state = abi.decode(output, (bytes[]));
            } else {
                require(idx & IDX_VALUE_MASK < state.length, "Index out-of-bounds");
                // Check the first field is 0x20 (because we have only a single return value)
                uint256 argPtr;
                assembly {
                    argPtr := mload(add(output, 32))
                }
                require(
                    argPtr == 32,
                    "Only one return value permitted (variable)"
                );

                assembly {
                    // Overwrite the first word of the return data with the length - 32
                    mstore(add(output, 32), sub(mload(output), 32))
                    // Insert a pointer to the return data, starting at the second word, into state
                    mstore(
                        add(add(state, 32), mul(and(idx, IDX_VALUE_MASK), 32)),
                        add(output, 32)
                    )
                }
            }
        } else {
            require(idx & IDX_VALUE_MASK < state.length, "Index out-of-bounds");
            // Single word
            require(
                output.length == 32,
                "Only one return value permitted (static)"
            );

            state[idx & IDX_VALUE_MASK] = output;
        }

        return state;
    }

    function writeTuple(
        bytes[] memory state,
        bytes1 index,
        bytes memory output
    ) internal view {
        uint256 idx = uint8(index);
        if (idx == IDX_END_OF_ARGS) return;

        bytes memory entry = state[idx & IDX_VALUE_MASK] = new bytes(output.length + 32);
        memcpy(output, 0, entry, 32, output.length);
        assembly {
            let l := mload(output)
            mstore(add(entry, 32), l)
        }
    }

    function memcpy(
        bytes memory src,
        uint256 srcIdx,
        bytes memory dest,
        uint256 destIdx,
        uint256 len
    ) internal view {
        assembly {
            pop(
                staticcall(
                    gas(),
                    4,
                    add(add(src, 32), srcIdx),
                    len,
                    add(add(dest, 32), destIdx),
                    len
                )
            )
        }
    }
}