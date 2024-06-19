// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseVelodromeCompounder, VelodromeTradeLibrary, Route, IRouter, SwapStep} from "./BaseVelodromeCompounder.sol";
import {ILpToken} from "./VelodromeTradeLibrary.sol";

abstract contract BaseVelodromeLpCompounder is BaseVelodromeCompounder {
    using SafeERC20 for IERC20;

    error CompoundFailed();

    function sellRewardsForLpTokenViaVelodrome(address vaultAsset, bytes memory data) internal {
        sellRewardsViaVelodrome();

        VelodromeTradeLibrary.addLiquidity(velodromeRouter, vaultAsset);

        uint256 amount = IERC20(vaultAsset).balanceOf(address(this));
        uint256 minOut = abi.decode(data, (uint256));
        if (amount < minOut) revert CompoundFailed();
    }

    function setVelodromeLpCompounderValues(
        address newVelodromeRouter,
        address lpToken,
        address[] memory rewTokens,
        SwapStep[] memory newTradePaths
    ) internal {
        address oldRouter = address(velodromeRouter);

        setVelodromeTradeValues(newVelodromeRouter, rewTokens, newTradePaths);

        (address tokenA, address tokenB) = ILpToken(lpToken).tokens();

        // Reset old router
        if(oldRouter != address(0)) {
            IERC20(tokenA).forceApprove(address(oldRouter), 0);
            IERC20(tokenB).forceApprove(address(oldRouter), 0);
        }

        // approve and set new base asset
        IERC20(tokenA).forceApprove(newVelodromeRouter, type(uint256).max);
        IERC20(tokenB).forceApprove(newVelodromeRouter, type(uint256).max);
    }
}
