// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

interface IBaseAdapter {
    function deposit(uint256 amount) external;

    function _depositUnderlying(uint256 amount) external;

    function _depositLP(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function _withdrawUnderlying(uint256 amount) external;

    function _withdrawLP(uint256 amount) external;

    function totalAssets() external view returns (uint256);

    function _totalUnderlying() external view returns (uint256);

    function _totalLP() external view returns (uint256);

    function rewardTokens() external view returns (address[] memory);

    function _claimRewards() external;

    function underlying() external view returns (address);

    function lpToken() external view returns (address);
}
