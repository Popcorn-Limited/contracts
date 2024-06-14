// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseAdapter, Errors, IPriceOracle} from "./BaseAdapter.sol";
import {IAToken} from "src/interfaces/external/aave/IAaveV3.sol";

/// @title AaveV3 Oracle
/// @author RedVeil
/// @notice Adapter for pricing aToken to their underlying asset
contract AaveV3Oracle is BaseAdapter {
    /// @inheritdoc IPriceOracle
    string public constant name = "AaveV3Oracle";

    error WrongAsset();

    /// @notice Get a quote for aToken
    /// @dev Since the underlying balance of assets in aToken is equal to the supply of aToken we simply return 1:1
    /// @param inAmount The amount of `base` to convert.
    /// @param base The token that is being priced. Either `aToken` or `underlying`.
    /// @param quote The token that is the unit of account. Either `underlying` or `aToken`.
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
