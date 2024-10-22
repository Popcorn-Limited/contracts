// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.0
pragma solidity ^0.8.25;

interface ILBClaimer {
    function claim(address user, uint256[] memory ids) external;
}
