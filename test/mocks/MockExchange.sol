// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract MockExchange {
    constructor() {}

    function swapTokenExactAmountIn(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin
    ) external returns (uint256) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        IERC20(tokenOut).transfer(msg.sender, amountOutMin);
        return amountOutMin;
    }
}
