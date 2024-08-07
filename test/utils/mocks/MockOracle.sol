// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

contract MockOracle {
    mapping(address => mapping(address => uint256)) public prices;

    function setPrice(address base, address quote, uint256 price) external {
        if (price == 0) {
            prices[base][quote] = 0;
            prices[quote][base] = 0;
        } else {
            prices[base][quote] = price;
            prices[quote][base] = 1e18 * 1e18 / price;
        }
    }

    function getQuote(uint inAmount, address base, address quote) external view returns (uint) {
        return prices[base][quote] == 0 ? inAmount : prices[base][quote] * inAmount / 1e18;
    }
}