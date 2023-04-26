// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IUniswapRouterV2} from "../../../../interfaces/external/uni/IUniswapRouterV2.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract UniV2Router {
    using SafeERC20 for IERC20;

    address router;

    constructor(address _router) {
        router = _router;
    }

    function trade(
        address[] memory route,
        uint256 amount,
        uint256 minAmount
    ) external returns (uint256) {
        IERC20(route[0]).transferFrom(msg.sender, address(this), amount);

        uint256[] memory amountsOut = IUniswapRouterV2(router)
            .swapExactTokensForTokens(
                amount,
                minAmount,
                route,
                msg.sender,
                block.timestamp
            );

        uint256 len = route.length;
        IERC20(route[len - 1]).safeTransfer(msg.sender, amountsOut[len - 1]);
        return amountsOut[len - 1];
    }
}
