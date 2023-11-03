// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

abstract contract BaseLeveragedStrategy {
    function _enterLeveragedPosition(uint256 amount, uint256 leverage) internal virtual;
    function _exitLeveragedPosition(uint256 leverage) internal virtual;
}
