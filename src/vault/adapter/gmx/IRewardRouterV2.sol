// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

interface IRewardRouterV2 {
    function feeGlpTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);

    function stakeGmx(uint256 _amount) external;
    function stakeEsGmx(uint256 _amount) external;
    function unstakeGmx(uint256 _amount) external;
    function unstakeEsGmx(uint256 _amount) external;

    function gmx() external view returns(address);
    function stakedGmxTracker() external view returns(address);
}