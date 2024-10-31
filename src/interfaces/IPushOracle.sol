// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IPriceOracle} from "./IPriceOracle.sol";

interface IPushOracle is IPriceOracle {
    function setPrice(
        address base,
        address quote,
        uint256 bqPrice,
        uint256 qbPrice
    ) external;

    function setPrices(
        address[] memory bases,
        address[] memory quotes,
        uint256[] memory bqPrices,
        uint256[] memory qbPrices
    ) external;

    function prices(
        address base,
        address quote
    ) external view returns (uint256);
}