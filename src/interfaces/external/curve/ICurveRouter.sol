// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;


interface ICurveRouter {
    function exchange(
        address pool,
        address from,
        address to,
        uint256 amount,
        uint256 expected
    ) external returns (uint256);

    function exchange_multiple(
        address[9] memory route,
        uint256[3][4] memory swap_params,
        uint256 amount,
        uint256 expected
    ) external returns (uint256);
}