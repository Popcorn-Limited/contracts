// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

interface IUniV3Pool {
    function observe(uint32[] memory secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}
