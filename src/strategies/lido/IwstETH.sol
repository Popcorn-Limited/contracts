// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.25;

interface IwstETH {
    // Returns amount of wstETH for a given amount of stETH
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    // Returns amount of stETH for a given amount of wstETH
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

    // Exchanges wstETH to stETH - return amount of stETH received
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}
