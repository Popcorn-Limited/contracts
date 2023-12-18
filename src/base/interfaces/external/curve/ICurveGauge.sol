// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

interface ICurveGauge {
    function deposit(uint256 amount, address recipient) external;

    function withdraw(uint256 amount) external;
}
