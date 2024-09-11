// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

interface IETHxStaking {
    // returns the amount of ETH equivalent to 1 ETHx - 18 decimals
    function getExchangeRate() external view returns (uint256 ethAmount);

    // stake ETH sent as value, mints ethX to receiver according to exchange rate
    function deposit(address receiver) payable external returns (uint256 ethXAmountMinted);
}