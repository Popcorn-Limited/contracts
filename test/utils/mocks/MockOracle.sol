// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

contract MockOracle {
    mapping(address => mapping(address => uint256)) public prices;

    function setPrice(address base, address quote, uint256 price) external {
        prices[base][quote] = price;
    }

    function getQuote(uint inAmount, address base, address quote) external view returns (uint) {
        return prices[base][quote] == 0 ? inAmount : prices[base][quote];
    }
}