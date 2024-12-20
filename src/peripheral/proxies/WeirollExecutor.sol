// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {VM} from "weiroll/VM.sol";

contract WeirollExecutor is VM {
    constructor() VM() {}

    function execute(bytes32[] calldata commands, bytes[] memory state)
        external
        returns (bytes[] memory)
    {
        return _execute(commands, state);
    }
}