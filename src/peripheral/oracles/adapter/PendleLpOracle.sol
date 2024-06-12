// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.23

pragma solidity ^0.8.23;

import {BaseAdapter, Errors, IPriceOracle} from "./BaseAdapter.sol";
import {ScaleUtils, Scale} from "src/lib/ScaleUtils.sol";

interface IPendleMarket {
    function readTokens()
        external
        view
        returns (address _SY, address _PT, address _YT);
}

interface IYieldToken {
    function yieldToken() external view returns (address);
}

interface IPendleOracle {
    function getLpToAssetRate(
        address market,
        uint32 duration
    ) external view returns (uint256);
}

interface IPendleMarketFactory {
    function isValidMarket(address market) external view returns (bool);
}

/// @title PendleLp Oracle
/// @author RedVeil
/// @notice Adapter for pricing pendle lp token to their underlying asset
contract PendleLpOracle is BaseAdapter {
    /// @dev The minimum length of the TWAP window.
    uint32 internal constant MIN_TWAP_WINDOW = 5 minutes;

    /// @inheritdoc IPriceOracle
    string public constant name = "PendleLpOracle";

    /// @notice The desired length of the twap window.
    uint32 public immutable twapWindow;

    IPendleOracle public immutable pendleOracle;
    IPendleMarketFactory public immutable pendleMarketFactory;

    /// @param _twapWindow The desired length of the twap window.
    /// @param _pendleOracle The address of the Pendle Oracle
    /// @param _pendleMarketFactory The address of the Pendle Market Factory.
    constructor(
        uint32 _twapWindow,
        address _pendleOracle,
        address _pendleMarketFactory
    ) {
        if (
            _twapWindow < MIN_TWAP_WINDOW ||
            _twapWindow > uint32(type(int32).max)
        ) {
            revert Errors.PriceOracle_InvalidConfiguration();
        }

        twapWindow = _twapWindow;
        pendleOracle = IPendleOracle(_pendleOracle);
        pendleMarketFactory = IPendleMarketFactory(_pendleMarketFactory);
    }

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
        bool inverse;
        address market;
        address underlying;

        if (pendleMarketFactory.isValidMarket(base)) {
            _checkUnderlying(base, quote);
            market = base;
            underlying = quote;
        } else {
            if (pendleMarketFactory.isValidMarket(quote)) {
                _checkUnderlying(quote, base);
                inverse = true;
                market = quote;
                underlying = base;
            } else {
                revert Errors.PriceOracle_NotSupported(base, quote);
            }
        }

        uint8 marketDecimals = _getDecimals(market);
        Scale scale = ScaleUtils.calcScale(
            marketDecimals,
            _getDecimals(underlying),
            marketDecimals
        );
        uint256 price = pendleOracle.getLpToAssetRate(market, twapWindow);

        return ScaleUtils.calcOutAmount(inAmount, price, scale, inverse);
    }

    function _checkUnderlying(
        address market,
        address underlying
    ) internal view {
        (address sy, , ) = IPendleMarket(market).readTokens();
        if (IYieldToken(sy).yieldToken() != underlying)
            revert Errors.PriceOracle_NotSupported(market, underlying);
    }
}
