// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

import {ICToken} from "./ICompoundV2.sol";
import "forge-std/console.sol";

/// @notice Get up to date cToken data without mutating state.
/// @author Transmissions11 (https://github.com/transmissions11/libcompound)
library LibCompound {
    using FixedPointMathLib for uint256;
    using Math for uint256;

    function viewUnderlyingBalanceOf(ICToken cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulWadDown(viewExchangeRate(cToken));
    }

    function toUnderlyingAmount(ICToken cToken, uint256 cTokenAmount) internal view returns (uint256) {
        return cTokenAmount.mulWadDown(viewExchangeRate(cToken));
    }

    function toCTokenAmount(ICToken cToken, uint256 amount) internal view returns (uint256) {
        return amount.divWadUp(viewExchangeRate(cToken));
    }

    function viewExchangeRate(ICToken cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockTimestamp();

        if (accrualBlockNumberPrior == block.timestamp) {
            return cToken.exchangeRateStored();
        }

        uint256 totalCash = cToken.getCash();
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();

        uint256 borrowRateMantissa = cToken.borrowRatePerTimestamp();

        require(borrowRateMantissa <= 0.0005e16, "RATE_TOO_HIGH"); // Same as borrowRateMaxMantissa in ICTokenInterfaces.sol

        uint256 interestAccumulated =
            (borrowRateMantissa * (block.timestamp - accrualBlockNumberPrior)).mulWadDown(borrowsPrior);

        uint256 totalReserves = cToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = cToken.totalSupply();

        // Reverts if totalSupply == 0
        return (totalCash + totalBorrows - totalReserves).divWadDown(totalSupply);
    }

    // calculates real time borrow balance
    function viewBorrowBalance(ICToken cToken, address user) internal view returns (uint256) {
        // Get stored borrow balance and last update block
        uint256 storedBorrowBalance = cToken.borrowBalanceStored(user);
        uint256 lastUpdateBlock = cToken.accrualBlockTimestamp();
        uint256 currentBlockNumber = block.timestamp;

        if (lastUpdateBlock == currentBlockNumber) {
            return storedBorrowBalance;
        }

        // Get the borrow index on last update
        uint256 borrowIndex = cToken.borrowIndex();

        // Calculate the current borrow index (with accrued interest)
        uint256 currentBorrowIndex = borrowIndex + (cToken.borrowRatePerTimestamp() * (currentBlockNumber - lastUpdateBlock));

        // Calculate the updated borrow balance (including accrued interest)
        return (storedBorrowBalance * currentBorrowIndex) / borrowIndex;
    }

    /// @notice The amount of compound shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(uint256 shares, uint256 totalSupply, uint256 adapterCTokenBalance)
        public
        pure
        returns (uint256)
    {
        return totalSupply == 0 ? shares : shares.mulDivUp(adapterCTokenBalance, totalSupply);
    }
}
