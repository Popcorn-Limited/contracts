// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

interface ICToken {
    /**
     * @dev Returns the address of the underlying asset of this cToken
     *
     */
    function underlying() external view returns (address);

    /**
     * @dev Returns the symbol of this cToken
     *
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the address of the comptroller
     *
     */
    function comptroller() external view returns (address);

    function balanceOf(address) external view returns (uint256);

    /**
     * @dev Send underlying to mint cToken. - returns 0 for success
     *
     */
    function mint(uint256) external returns (uint256 success);

    function redeem(uint256) external;

    function borrow(uint256 borrowAmount) external returns (uint256);
    

    function redeemUnderlying(uint256) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    /**
     * @dev Returns exchange rate from the underlying to the cToken.
     *
     */
    function exchangeRateStored() external view returns (uint256);

    function borrowBalanceStored(address user) external view returns (uint256);

    function getCash() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function borrowIndex() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function borrowRatePerTimestamp() external view returns (uint256);

    function reserveFactorMantissa() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function accrualBlockTimestamp() external view returns (uint256);

    function balanceOfUnderlying(address owner) external view returns (uint256);

    function exchangeRateCurrent() external;
}

interface IComptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);

    /**
     * @dev Returns the address of the underlying asset of this cToken
     *
     */
    function getCompAddress() external view returns (address);

    /**
     * @dev Returns the address of the underlying asset of this cToken
     *
     */
    function compSpeeds(address) external view returns (uint256);

    function compSupplySpeeds(address) external view returns (uint256);

    /**
     * @dev Returns the isListed, collateralFactorMantissa, and isCompred of the cToken market
     *
     */
    function markets(address) external view returns (bool, uint256, bool);

    function claimComp(address holder) external;
}
