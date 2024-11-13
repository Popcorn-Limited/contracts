// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.12 <0.9.0;
import "forge-std/console.sol";

struct ParamRule {
    bool dynamicParam; // if the param to extract is dynamic in length
    uint256 argPosition; // position of the argument starting from 0
    bool recursive; // if the param is inside the dynamic encoded value
    uint256 internalArgPosition; 
    bytes comparedValue; // ie permitted value to check against // TODO array of values allowed?
}

contract ParamsGuard {
    mapping(bytes4 => ParamRule) callParamRule;

    function setRule(bytes4 sig, ParamRule memory rule) external {
        callParamRule[sig] = rule;
    }

    function verifyTxData(
        bytes memory txData
    ) external view returns (bytes memory param) {
        // TODO refactor to support multiple allowed rules - pass if one rule is satisfied
        // for(uint i=0; i<paramRules.length; i++) {
        ParamRule memory rule = callParamRule[bytes4(txData)];

        if (!rule.dynamicParam) {
            // load the param to verify
            param = staticParam(txData, rule.argPosition);

            // if the bytes contains an encoding of multiple variables
            if(rule.recursive)
                param = recursiveStaticParam(param, rule.internalArgPosition);

            console.log(param.length);
            console.logBytes(param);
        } else {
            // dynamic param - get the actual value inside
            param = dynamicParam(txData, rule.argPosition);

            if(rule.recursive)
                param = recursiveStaticParam(param, rule.internalArgPosition);
        }

        // compare
        require(
            keccak256(param) == keccak256(rule.comparedValue),
            "Value is not valid"
        );
        console.log("TRUE");
    }

    function staticParam(
        bytes memory data,
        uint256 argPosition
    ) internal pure returns (bytes memory varToCheck) {
        assembly {
            // variable is stored directly at the position 32 + position * 32 bytes slot
            let argOffsetPosition := add(32, add(4, mul(argPosition, 32)))

            // find position in actual memory where the offset of the arg in data is stored
            let offsetPositionInMemory := add(data, argOffsetPosition)

            // set free memory pointer
            varToCheck := mload(0x40)

            // store the length (32)
            mstore(varToCheck, 32)

            // set space - 32 for length + 32 for value
            mstore(0x40, add(varToCheck, 64))

            // copy data
            mstore(add(varToCheck, 32), mload(offsetPositionInMemory))
        }
    }

    function recursiveStaticParam(
        bytes memory data,
        uint256 argPosition
    ) internal pure returns (bytes memory varToCheck) {
         assembly {
            // variable is stored directly at the position 32 + position * 32 bytes slot
            let argOffsetPosition := add(32, mul(argPosition, 32))

            // find position in actual memory where the offset of the arg in data is stored
            let offsetPositionInMemory := add(data, argOffsetPosition)

            // set free memory pointer
            varToCheck := mload(0x40)

            // store the length (32)
            mstore(varToCheck, 32)

            // set space - 32 for length + 32 for value
            mstore(0x40, add(varToCheck, 64))

            // copy data
            mstore(add(varToCheck, 32), mload(offsetPositionInMemory))
        }
    }

    // function recursiveDynamicParam(
    //     bytes memory data,
    //     uint256 argPosition
    // ) internal pure returns (bytes memory varToCheck) {
    //     // data is stored as
    //     // first 32 bytes with length

    //     // a dynamic param is stored as
    //     // offset in data stored at argPosition*32
    //     // at the offset the length of the data is stored in 32 bytes
    //     // after that the actual data is stored
    //     assembly {
    //         // calculate position in data of the arg to retrieve
    //         // 32 (length of data) + 4 (function sig within data) + argPosition * 32
    //         let argOffsetPosition := add(32, mul(argPosition, 32))

    //         // find position in actual memory where the offset of the arg in data is stored
    //         let offsetPositionInMemory := add(data, argOffsetPosition)

    //         // load the argument offset within data, excluding the 4bytes sig
    //         let targetArgumentOffset := mload(offsetPositionInMemory)

    //         // get the starting position of the variable’s data in memory
    //         // 32 + targetArgumentOffset
    //         let lengthPositionInMemory := add(
    //             add(data, 32),
    //             targetArgumentOffset
    //         )

    //         // The first 32 bytes at lengthPositionInMemory represent the length of the target variable.
    //         let dataLength := mload(lengthPositionInMemory)

    //         // find the position where the actual data starts, skipping the memory
    //         let dataStartInMemory := add(lengthPositionInMemory, 32)

    //         // Allocate memory and store its length + 32 for the size
    //         varToCheck := mload(0x40)

    //         // store the return data size
    //         mstore(varToCheck, dataLength)

    //         // update free pointer
    //         mstore(0x40, add(varToCheck, add(32, dataLength)))

    //         // Copy the data from source to destination
    //         for {
    //             let i := 0
    //         } lt(i, dataLength) {
    //             i := add(i, 0x20)
    //         } {
    //             mstore(
    //                 add(add(varToCheck, 32), i),
    //                 mload(add(dataStartInMemory, i))
    //             )
    //         }
    //     }
    // }

    // retrieves a dynamic parameter 
    // data is encoded as a transaction call 
    function dynamicParam(
        bytes memory data,
        uint256 argPosition
    ) internal pure returns (bytes memory varToCheck) {
        // data is stored as
        // first 32 bytes with length
        // next 4 bytes function sig + 32 bytes slots with argss

        // a dynamic param is stored as
        // offset in data stored at 4 + argPosition*32
        // at the offset the length of the data is stored in 32 bytes
        // after that the actual data is stored
        assembly {
            // calculate position in data of the arg to retrieve
            // 32 (length of data) + 4 (function sig within data) + argPosition * 32
            let argOffsetPosition := add(32, add(4, mul(argPosition, 32)))

            // find position in actual memory where the offset of the arg in data is stored
            let offsetPositionInMemory := add(data, argOffsetPosition)

            // load the argument offset within data, excluding the 4bytes sig
            let targetArgumentOffset := mload(offsetPositionInMemory)

            // get the starting position of the variable’s data in memory
            // 32 + 4 + targetArgumentOffset
            let lengthPositionInMemory := add(
                add(data, 36),
                targetArgumentOffset
            )

            // The first 32 bytes at lengthPositionInMemory represent the length of the target variable.
            let dataLength := mload(lengthPositionInMemory)

            // find the position where the actual data starts, skipping the memory
            let dataStartInMemory := add(lengthPositionInMemory, 32)

            // Allocate memory and store its length + 32 for the size
            varToCheck := mload(0x40)

            // store the return data size
            mstore(varToCheck, dataLength)

            // update free pointer
            mstore(0x40, add(varToCheck, add(32, dataLength)))

            // Copy the data from source to destination
            for {
                let i := 0
            } lt(i, dataLength) {
                i := add(i, 0x20)
            } {
                mstore(
                    add(add(varToCheck, 32), i),
                    mload(add(dataStartInMemory, i))
                )
            }
        }
    }
}
