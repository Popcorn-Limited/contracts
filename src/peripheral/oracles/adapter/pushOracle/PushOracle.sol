// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {Owned} from "src/utils/Owned.sol";
import {ScaleUtils, Scale} from "src/lib/euler/ScaleUtils.sol";
import {BaseAdapter, Errors, IPriceOracle} from "../BaseAdapter.sol";

contract PushOracle is BaseAdapter, Owned {
    /// @inheritdoc IPriceOracle
    string public constant name = "PushOracle";

    mapping(address => mapping(address => uint256)) public prices;

    event PriceUpdated(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    );

    error Misconfigured();

    constructor(address _owner) Owned(_owner) {}

    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external onlyOwner {
        // Both prices must be set
        if ((bqPrice == 0 && qbPrice != 0) || (qbPrice == 0 && bqPrice != 0))
            revert Misconfigured();

        prices[base][quote] = bqPrice;
        prices[quote][base] = qbPrice;

        emit PriceUpdated(base, quote, bqPrice, qbPrice);
    }

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
}
