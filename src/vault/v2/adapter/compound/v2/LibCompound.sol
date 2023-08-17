// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";


import {ICToken} from "./ICompoundV2.sol";

/// @notice Get up to date cToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibCompound {
    using FixedPointMathLib for uint256;
    using Math for uint256;


    function viewUnderlyingBalanceOf(ICToken cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulWadDown(viewExchangeRate(cToken));
    }

    function viewExchangeRate(ICToken cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (accrualBlockNumberPrior == block.number) return cToken.exchangeRateStored();

        uint256 totalCash = cToken.getCash();
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();

        uint256 borrowRateMantissa = cToken.borrowRatePerBlock();

        require(borrowRateMantissa <= 0.0005e16, "RATE_TOO_HIGH"); // Same as borrowRateMaxMantissa in ICTokenInterfaces.sol

        uint256 interestAccumulated = (borrowRateMantissa * (block.number - accrualBlockNumberPrior)).mulWadDown(
            borrowsPrior
        );

        uint256 totalReserves = cToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = cToken.totalSupply();

        // Reverts if totalSupply == 0
        return (totalCash + totalBorrows - totalReserves).divWadDown(totalSupply);
    }

    /// @notice The amount of compound shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256 shares,
        uint256 totalSupply,
        uint256 adapterCTokenBalance
    ) public pure returns (uint256) {

        return
            totalSupply == 0
                ? shares
                : shares.mulDivUp(
                adapterCTokenBalance,
                totalSupply
            );
    }
}
