// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

interface IStrategyWithData {
    function withdrawWithData(
        uint256 assets, 
        address receiver, 
        address owner, 
        bytes calldata extraData
    ) external returns (uint256 shares);
}
