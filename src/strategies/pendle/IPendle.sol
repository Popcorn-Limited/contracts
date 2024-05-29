// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/*
 *******************************************************************************************************************
 *******************************************************************************************************************
 * NOTICE *
 * Refer to https://docs.pendle.finance/Developers/Contracts/PendleRouter for more information on
 * TokenInput, TokenOutput, ApproxParams, LimitOrderData
 * It's recommended to use Pendle's Hosted SDK to generate the params
 *******************************************************************************************************************
 *******************************************************************************************************************
 */

enum OrderType {
    SY_FOR_PT,
    PT_FOR_SY,
    SY_FOR_YT,
    YT_FOR_SY
}

struct Order {
    uint256 salt;
    uint256 expiry;
    uint256 nonce;
    OrderType orderType;
    address token;
    address YT;
    address maker;
    address receiver;
    uint256 makingAmount;
    uint256 lnImpliedRate;
    uint256 failSafeRate;
    bytes permit;
}

struct FillOrderParams {
    Order order;
    bytes signature;
    uint256 makingAmount;
}

// if not using LimitOrder, leave alla fields empty
struct LimitOrderData {
    address limitRouter;
    uint256 epsSkipMarket;
    FillOrderParams[] normalFills;
    FillOrderParams[] flashFills;
    bytes optData;
}

struct ApproxParams {
    uint256 guessMin;
    uint256 guessMax;
    uint256 guessOffchain;
    uint256 maxIteration;
    uint256 eps;
}

enum SwapType {
    NONE,
    KYBERSWAP,
    ONE_INCH,
    // ETH_WETH not used in Aggregator
    ETH_WETH
}

struct SwapData {
    SwapType swapType;
    address extRouter;
    bytes extCalldata;
    bool needScale;
}

struct TokenInput {
    // TOKEN DATA
    address tokenIn;
    uint256 netTokenIn;
    address tokenMintSy;
    // AGGREGATOR DATA
    address pendleSwap;
    SwapData swapData;
}

struct TokenOutput {
    // TOKEN DATA
    address tokenOut;
    uint256 minTokenOut;
    address tokenRedeemSy;
    // AGGREGATOR DATA
    address pendleSwap;
    SwapData swapData;
}

interface IPendleRouter {
    function addLiquiditySingleToken(
        address receiver,
        address market,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netLpOut, uint256 netSyFee, uint256 netSyInterm);

    function removeLiquiditySingleToken(
        address receiver,
        address market,
        uint256 netLpToRemove,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);
}

interface IPendleRouterStatic {
    function removeLiquiditySingleTokenStatic(address market, uint256 netLpToRemove, address tokenOut)
        external
        view
        returns (
            uint256 netTokenOut,
            uint256 netSyFee,
            uint256 priceImpact,
            uint256 exchangeRateAfter,
            uint256 netSyOut,
            uint256 netSyFromBurn,
            uint256 netPtFromBurn,
            uint256 netSyFromSwap
        );
}

interface IPendleMarket is IERC20 {
    // return pendle tokens of a market
    function readTokens() external view returns (address _SY, address _PT, address _YT);

    // return reward tokens
    function getRewardTokens() external view returns (address[] memory);

    // claim rewards in the same order as reward tokens
    function redeemRewards(address user) external returns (uint256[] memory);

    function increaseObservationsCardinalityNext(uint16 cardinalityNext) external;
}

interface IPendleSYToken {
    // returns all tokens that can mint this SY token
    function getTokensIn() external view returns (address[] memory);

    // returns all tokens that can be redeemed from this SY token
    function getTokensOut() external view returns (address[] memory);

    function totalSupply() external view returns (uint256);
    
    // returns exchange rate with underlying
    function exchangeRate() external view returns(uint256);
}

interface ISYTokenV3 is IPendleSYToken {
    // returns all tokens that can mint this SY token
    function supplyCap() external view returns (uint256);
}

interface IPendleGauge {
    function totalActiveSupply() external view returns (uint256);

    function activeBalance(address user) external view returns (uint256);

    /// @notice Redeem all accrued rewards, returning amountOuts in the same order as getRewardTokens.
    function redeemRewards(address user) external returns (uint256[] memory);

    /// @notice Returns the list of reward tokens being distributed
    function getRewardTokens() external view returns (address[] memory);
}

interface IPendleOracle {
    // returns exchange rate between lp token and underlying
    // duration is timestamp remaining till market expiry
    function getLpToAssetRate(address market, uint32 duration) external view returns (uint256 ptToAssetRate);

    function getLpToSyRate(address market, uint32 duration) external view returns (uint256 ptToSyRate);

    function getOracleState(address market, uint32 duration)
        external
        view
        returns (bool increaseCardinalityRequired, uint16 cardinalityRequired, bool oldestObservationSatisfied);
}
