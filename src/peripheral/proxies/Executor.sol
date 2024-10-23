// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

contract Executor {
    constructor() {}

    function execute(
        bytes32[] calldata targets,
        bytes[] memory calls
    ) external returns (bytes[] memory) {
        if (targets.length != calls.length) revert("Length mismatch");
        return _execute(targets, calls);
    }

    function _execute(
        bytes32[] calldata targets,
        bytes[] memory calls
    ) internal returns (bytes[] memory) {
        for (uint256 i; i < targets.length; i++) {
            (bool success, ) = address(uint160(uint256(targets[i]))).call(
                calls[i]
            );
            if (!success) revert("Call failed");
        }
    }
}
