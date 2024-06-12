// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.23

pragma solidity ^0.8.23;

import {BaseAdapter, Errors, IPriceOracle} from "./BaseAdapter.sol";
import {IAToken} from "src/interfaces/external/aave/IAaveV3.sol";

/// @title AaveV3 Oracle
/// @author RedVeil
/// @notice Adapter for pricing aToken to their underlying asset
contract AaveV3Oracle is BaseAdapter {
    /// @inheritdoc IPriceOracle
    string public constant name = "AaveV3Oracle";

    error WrongAsset();

    /// @notice Get a quote by querying the exchange rate from the stEth contract.
    /// @dev Calls `getSharesByPooledEth` for stEth/wstEth and `getPooledEthByShares` for wstEth/stEth.
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced. Either `stEth` or `wstEth`.
    /// @param quote The token that is the unit of account. Either `wstEth` or `stEth`.
    /// @return The converted amount.
    function _getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) internal view override returns (uint256) {
        try IAToken(base).UNDERLYING_ASSET_ADDRESS() returns (
            address underlying
        ) {
            if (underlying != quote) revert WrongAsset();
            return inAmount;
        } catch {
            if (IAToken(quote).UNDERLYING_ASSET_ADDRESS() != base)
                revert WrongAsset();
            return inAmount;
        }

        revert Errors.PriceOracle_NotSupported(base, quote);
    }
}
