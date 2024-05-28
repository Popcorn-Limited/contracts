// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

interface IOwned {
    function owner() external view returns (address);

    function nominatedOwner() external view returns (address);

    function nominateNewOwner(address owner) external;

    function acceptOwnership() external;
}
