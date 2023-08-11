// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IBaseAdapter {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function totalAssets() external view returns (uint256);

    function rewardTokens() external view returns (address[] memory);

    function underlying() external view returns (address);

    function lpToken() external view returns (address);

    function useLpToken() external view returns (bool);
}
