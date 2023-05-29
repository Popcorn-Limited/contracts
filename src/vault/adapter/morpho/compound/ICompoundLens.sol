// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Types} from "../Types.sol";

interface ICompoundLens {
    function isMarketCreated(address _poolToken) external view returns (bool);

    function getMarketPauseStatus(
        address _poolToken
    ) external view returns (Types.MarketPauseStatus memory);

    function getCurrentSupplyBalanceInOf(
        address _poolToken,
        address _user
    )
        external
        view
        returns (
            uint256 balanceOnPool,
            uint256 balanceInP2P,
            uint256 totalBalance
        );
}
