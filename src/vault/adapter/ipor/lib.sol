// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IIpToken, IAmmPoolsLens, IAmmPoolsService} from "./IIPorProtocol.sol";


library LibIpor {
    using FixedPointMathLib for uint256;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function viewUnderlyingBalanceOf(
        IIpToken ipToken,
        IAmmPoolsLens ammPoolsLens,
        address asset,
        address user
    ) internal view returns (uint256) {
        return ipToken.balanceOf(user).mulWadDown(viewExchangeRate(ammPoolsLens, asset));
    }

    function viewExchangeRate(
        IAmmPoolsLens ammPoolsLens,
        address asset
    ) internal view returns (uint256) {
        return ammPoolsLens.getIpTokenExchangeRate(asset);
    }
}
