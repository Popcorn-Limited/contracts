// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ICurveMetapool} from "../../../../interfaces/external/curve/ICurveMetapool.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract CurveMetapool {
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

        ICurveMetapool(router).add_liquidity([bal0, 0], 0);

        uint256 bal = IERC20(lpToken).balanceOf(address(this));
        IERC20(lpToken).safeTransfer(msg.sender, bal);
        return bal;
    }
}