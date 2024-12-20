// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Owned} from "src/utils/Owned.sol";
import {ScaleUtils, Scale} from "src/lib/euler/ScaleUtils.sol";
import {BaseAdapter, Errors, IPriceOracle} from "../BaseAdapter.sol";

/**
 * @title   PushOracle
 * @author  RedVeil
 * @notice  A simple oracle that allows for setting prices for base/quote pairs by permissioned entities
 * @dev     The safety and reliability of these prices must be handled by other contracts/infrastructure
 */
contract PushOracle is BaseAdapter, Owned {
    /// @inheritdoc IPriceOracle
    string public constant name = "PushOracle";

    /// @dev base => quote => price
    mapping(address => mapping(address => uint256)) public prices;

    event PriceUpdated(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    );

    error Misconfigured();

    constructor(address _owner) Owned(_owner) {}

    /*//////////////////////////////////////////////////////////////
                        SET PRICE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the price of a base/quote pair
     * @param base The base asset
     * @param quote The quote asset
     * @param bqPrice The price of the base in terms of the quote
     * @param qbPrice The price of the quote in terms of the base
     */
    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external onlyOwner {
        _setPrice(base, quote, bqPrice, qbPrice);
    }

    /**
     * @notice Set the prices of multiple base/quote pairs
     * @param bases The base assets
     * @param quotes The quote assets
     * @param bqPrices The prices of the bases in terms of the quotes
     * @param qbPrices The prices of the quotes in terms of the bases
     * @dev The lengths of the arrays must be the same
     */
    function setPrices(
        address[] memory bases,
        address[] memory quotes,
        uint256[] memory bqPrices,
        uint256[] memory qbPrices
    ) external onlyOwner checkLength(bases.length, quotes.length) {
        _checkLength(bases.length, bqPrices.length);
        _checkLength(bases.length, qbPrices.length);

        for (uint256 i = 0; i < bases.length; i++) {
            _setPrice(bases[i], quotes[i], bqPrices[i], qbPrices[i]);
        }
    }

    /// @dev Internal function to set the price of a base/quote pair
    function _setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) internal {
        // Both prices must be set
        if ((bqPrice == 0 && qbPrice != 0) || (qbPrice == 0 && bqPrice != 0))
            revert Misconfigured();

        prices[base][quote] = bqPrice;
        prices[quote][base] = qbPrice;

        emit PriceUpdated(base, quote, bqPrice, qbPrice);
    }

    /*//////////////////////////////////////////////////////////////
                            QUOTE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to get the quote amount for a given base amount 
    function _getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) internal view override returns (uint256) {
        uint256 price = prices[base][quote];

        if (price == 0) revert Errors.PriceOracle_NotSupported(base, quote);

        uint8 baseDecimals = _getDecimals(base);
        uint8 quoteDecimals = _getDecimals(quote);
        Scale scale = ScaleUtils.calcScale(baseDecimals, quoteDecimals, 18);

        return
            ScaleUtils.calcOutAmount(
                inAmount,
                prices[base][quote],
                scale,
                false
            );
    }

    /*//////////////////////////////////////////////////////////////
                            UTILS
    //////////////////////////////////////////////////////////////*/

    /// @dev Modifier to check the lengths of two arrays
    modifier checkLength(uint256 lengthA, uint256 lengthB) {
        _checkLength(lengthA, lengthB);
        _;
    }

    /// @dev Internal function to check the lengths of two arrays
    function _checkLength(uint256 lengthA, uint256 lengthB) internal pure {
        if (lengthA != lengthB) revert Misconfigured();
    }
}
