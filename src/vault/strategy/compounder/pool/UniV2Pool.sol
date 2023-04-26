// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IUniswapRouterV2} from "../../../../interfaces/external/uni/IUniswapRouterV2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract UniV2Pool {
    using SafeERC20 for IERC20;

    function addLiquidity(
        address router,
        address lpToken,
        address[2] memory underlyingTokens,
        uint256 bal0,
        uint256 bal1
    ) external returns (uint256) {
        IERC20(underlyingTokens[0]).transferFrom(
            msg.sender,
            address(this),
            bal0
        );
        IERC20(underlyingTokens[1]).transferFrom(
            msg.sender,
            address(this),
            bal1
        );

        IUniswapRouterV2(router).addLiquidity(
            underlyingTokens[0],
            underlyingTokens[1],
            bal0,
            bal1,
            0,
            0,
            address(this),
            block.timestamp
        );

        uint256 bal = IERC20(lpToken).balanceOf(address(this));
        IERC20(lpToken).safeTransfer(msg.sender, bal);
        return bal;
    }
}