// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

interface IPausable {
    function paused() external view returns (bool);

    function pause() external;

    function unpause() external;
}
