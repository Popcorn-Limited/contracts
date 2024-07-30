// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

contract MockOracle {
    uint256 public price;

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function getQuote(uint inAmount, address base, address quote) external view returns (uint) {
        return price == 0 ? inAmount : price;
    }
}