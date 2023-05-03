// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseToAssetCompounder} from "./BaseToAssetCompounder.sol";

struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
}

interface ISwapRouter {
    function exactInput(
        ExactInputParams params
    ) external returns (uint256 amountOut);
}

contract UniV3Compounder is BaseToAssetCompounder {
    mapping(address => uint256) poolFee;

    function _trade(
        address router,
        address[] memory route,
        uint256 amount,
        bytes memory optionalData
    ) internal override {
        ISwapRouter(router).exactInput(
            ExactInputParams({
                path: abi.encodePacked(DAI, poolFee, USDC, poolFee, WETH9),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0
            })
        );
    }
}
