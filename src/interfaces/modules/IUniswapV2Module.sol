// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IUniswapV2Module {
    function swap(
        address _router,
        address[] memory _route,
        uint256 _amount
    ) external;

    function addLiquidity(
        address _router,
        address _lpToken0,
        address _lpToken1
    ) external;
}
