// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IBaseStrategy} from "../../../interfaces/IBaseStrategy.sol";

interface ILeverageAdapter is IBaseStrategy {
    function adjustLeverage(uint256 amount, bytes memory data) external;
}

enum AllowanceAction {
    FORBID,
    ALLOW
}

struct MultiCall {
    address target;
    bytes callData;
}

struct BalanceDelta {
    address token;
    int256 amount;
}

/// @notice Debt limits packed into a single slot
/// @param minDebt Minimum debt amount per credit account
/// @param maxDebt Maximum debt amount per credit account
struct DebtLimits {
    uint128 minDebt;
    uint128 maxDebt;
}

/// @notice Info on bad debt liquidation losses packed into a single slot
/// @param currentCumulativeLoss Current cumulative loss from bad debt liquidations
/// @param maxCumulativeLoss Max cumulative loss incurred before the facade gets paused
struct CumulativeLossParams {
    uint128 currentCumulativeLoss;
    uint128 maxCumulativeLoss;
}

/// @notice Collateral check params
/// @param collateralHints Optional array of token masks to check first to reduce the amount of computation
///        when known subset of account's collateral tokens covers all the debt
/// @param minHealthFactor Min account's health factor in bps in order not to revert
/// @param enabledTokensMaskAfter Bitmask of account's enabled collateral tokens after the multicall
/// @param revertOnForbiddenTokens Whether to revert on enabled forbidden tokens after the multicall
/// @param useSafePrices Whether to use safe pricing (min of main and reserve feeds) when evaluating collateral
struct FullCheckParams {
    uint256[] collateralHints;
    uint16 minHealthFactor;
    uint256 enabledTokensMaskAfter;
    bool revertOnForbiddenTokens;
    bool useSafePrices;
}

uint8 constant BOT_PERMISSIONS_SET_FLAG = 1;

uint8 constant DEFAULT_MAX_ENABLED_TOKENS = 4;
address constant INACTIVE_CREDIT_ACCOUNT_ADDRESS = address(1);

/// @notice Debt management type
///         - `INCREASE_DEBT` borrows additional funds from the pool, updates account's debt and cumulative interest index
///         - `DECREASE_DEBT` repays debt components (quota interest and fees -> base interest and fees -> debt principal)
///           and updates all corresponding state varibles (base interest index, quota interest and fees, debt).
///           When repaying all the debt, ensures that account has no enabled quotas.
enum ManageDebtAction {
    INCREASE_DEBT,
    DECREASE_DEBT
}

/// @notice Collateral/debt calculation mode
///         - `GENERIC_PARAMS` returns generic data like account debt and cumulative indexes
///         - `DEBT_ONLY` is same as `GENERIC_PARAMS` but includes more detailed debt info, like accrued base/quota
///           interest and fees
///         - `FULL_COLLATERAL_CHECK_LAZY` checks whether account is sufficiently collateralized in a lazy fashion,
///           i.e. it stops iterating over collateral tokens once TWV reaches the desired target.
///           Since it may return underestimated TWV, it's only available for internal use.
///         - `DEBT_COLLATERAL` is same as `DEBT_ONLY` but also returns total value and total LT-weighted value of
///           account's tokens, this mode is used during account liquidation
///         - `DEBT_COLLATERAL_SAFE_PRICES` is same as `DEBT_COLLATERAL` but uses safe prices from price oracle
enum CollateralCalcTask {
    GENERIC_PARAMS,
    DEBT_ONLY,
    FULL_COLLATERAL_CHECK_LAZY,
    DEBT_COLLATERAL,
    DEBT_COLLATERAL_SAFE_PRICES
}

struct CreditAccountInfo {
    uint256 debt;
    uint256 cumulativeIndexLastUpdate;
    uint128 cumulativeQuotaInterest;
    uint128 quotaFees;
    uint256 enabledTokensMask;
    uint16 flags;
    uint64 lastDebtUpdate;
    address borrower;
}

struct CollateralDebtData {
    uint256 debt;
    uint256 cumulativeIndexNow;
    uint256 cumulativeIndexLastUpdate;
    uint128 cumulativeQuotaInterest;
    uint256 accruedInterest;
    uint256 accruedFees;
    uint256 totalDebtUSD;
    uint256 totalValue;
    uint256 totalValueUSD;
    uint256 twvUSD;
    uint256 enabledTokensMask;
    uint256 quotedTokensMask;
    address[] quotedTokens;
    address _poolQuotaKeeper;
}

struct CollateralTokenData {
    address token;
    uint16 ltInitial;
    uint16 ltFinal;
    uint40 timestampRampStart;
    uint24 rampDuration;
}

struct RevocationPair {
    address spender;
    address token;
}

/// @title Credit facade V3 interface
interface ICreditFacadeV3 {
    function creditManager() external view returns (address);

    function degenNFT() external view returns (address);

    function weth() external view returns (address);

    function botList() external view returns (address);

    function maxDebtPerBlockMultiplier() external view returns (uint8);

    function maxQuotaMultiplier() external view returns (uint256);

    function expirable() external view returns (bool);

    function expirationDate() external view returns (uint40);

    function debtLimits() external view returns (uint128 minDebt, uint128 maxDebt);

    function lossParams() external view returns (uint128 currentCumulativeLoss, uint128 maxCumulativeLoss);

    function forbiddenTokenMask() external view returns (uint256);

    function canLiquidateWhilePaused(address) external view returns (bool);

    // ------------------ //
    // ACCOUNT MANAGEMENT //
    // ------------------ //

    function openCreditAccount(address onBehalfOf, MultiCall[] calldata calls, uint256 referralCode)
        external
        payable
        returns (address creditAccount);

    function closeCreditAccount(address creditAccount, MultiCall[] calldata calls) external payable;

    function liquidateCreditAccount(address creditAccount, address to, MultiCall[] calldata calls) external;

    function multicall(address creditAccount, MultiCall[] calldata calls) external payable;

    function botMulticall(address creditAccount, MultiCall[] calldata calls) external;

    function setBotPermissions(address creditAccount, address bot, uint192 permissions) external;

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function setExpirationDate(uint40 newExpirationDate) external;

    function setDebtLimits(uint128 newMinDebt, uint128 newMaxDebt, uint8 newMaxDebtPerBlockMultiplier) external;

    function setBotList(address newBotList) external;

    function setCumulativeLossParams(uint128 newMaxCumulativeLoss, bool resetCumulativeLoss) external;

    function setTokenAllowance(address token, AllowanceAction allowance) external;

    function setEmergencyLiquidator(address liquidator, AllowanceAction allowance) external;
}

// ----------- //
// PERMISSIONS //
// ----------- //

uint192 constant ADD_COLLATERAL_PERMISSION = 1;
uint192 constant INCREASE_DEBT_PERMISSION = 1 << 1;
uint192 constant DECREASE_DEBT_PERMISSION = 1 << 2;
uint192 constant ENABLE_TOKEN_PERMISSION = 1 << 3;
uint192 constant DISABLE_TOKEN_PERMISSION = 1 << 4;
uint192 constant WITHDRAW_COLLATERAL_PERMISSION = 1 << 5;
uint192 constant UPDATE_QUOTA_PERMISSION = 1 << 6;
uint192 constant REVOKE_ALLOWANCES_PERMISSION = 1 << 7;

uint192 constant EXTERNAL_CALLS_PERMISSION = 1 << 16;

uint256 constant ALL_CREDIT_FACADE_CALLS_PERMISSION = ADD_COLLATERAL_PERMISSION | WITHDRAW_COLLATERAL_PERMISSION
    | INCREASE_DEBT_PERMISSION | DECREASE_DEBT_PERMISSION | ENABLE_TOKEN_PERMISSION | DISABLE_TOKEN_PERMISSION
    | UPDATE_QUOTA_PERMISSION | REVOKE_ALLOWANCES_PERMISSION;

uint256 constant ALL_PERMISSIONS = ALL_CREDIT_FACADE_CALLS_PERMISSION | EXTERNAL_CALLS_PERMISSION;

// ----- //
// FLAGS //
// ----- //

/// @dev Indicates that there are enabled forbidden tokens on the account before multicall
uint256 constant FORBIDDEN_TOKENS_BEFORE_CALLS = 1 << 192;

/// @dev Indicates that external calls from credit account to adapters were made during multicall,
///      set to true on the first call to the adapter
uint256 constant EXTERNAL_CONTRACT_WAS_CALLED = 1 << 193;

/// @title Credit facade V3 multicall interface
/// @dev Unless specified otherwise, all these methods are only available in `openCreditAccount`,
///      `closeCreditAccount`, `multicall`, and, with account owner's permission, `botMulticall`
interface ICreditFacadeV3Multicall {
    /// @notice Updates the price for a token with on-demand updatable price feed
    /// @param token Token to push the price update for
    /// @param reserve Whether to update reserve price feed or main price feed
    /// @param data Data to call `updatePrice` with
    /// @dev Calls of this type must be placed before all other calls in the multicall not to revert
    /// @dev This method is available in all kinds of multicalls
    function onDemandPriceUpdate(address token, bool reserve, bytes calldata data) external;

    /// @notice Stores expected token balances (current balance + delta) after operations for a slippage check.
    ///         Normally, a check is performed automatically at the end of the multicall, but more fine-grained
    ///         behavior can be achieved by placing `storeExpectedBalances` and `compareBalances` where needed.
    /// @param balanceDeltas Array of (token, minBalanceDelta) pairs, deltas are allowed to be negative
    /// @dev Reverts if expected balances are already set
    /// @dev This method is available in all kinds of multicalls
    function storeExpectedBalances(BalanceDelta[] calldata balanceDeltas) external;

    /// @notice Performs a slippage check ensuring that current token balances are greater than saved expected ones
    /// @dev Resets stored expected balances
    /// @dev Reverts if expected balances are not stored
    /// @dev This method is available in all kinds of multicalls
    function compareBalances() external;

    /// @notice Adds collateral to account
    /// @param token Token to add
    /// @param amount Amount to add
    /// @dev Requires token approval from caller to the credit manager
    /// @dev This method can also be called during liquidation
    function addCollateral(address token, uint256 amount) external;

    /// @notice Adds collateral to account using signed EIP-2612 permit message
    /// @param token Token to add
    /// @param amount Amount to add
    /// @param deadline Permit deadline
    /// @dev `v`, `r`, `s` must be a valid signature of the permit message from caller to the credit manager
    /// @dev This method can also be called during liquidation
    function addCollateralWithPermit(address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    /// @notice Increases account's debt
    /// @param amount Underlying amount to borrow
    /// @dev Increasing debt is prohibited when closing an account
    /// @dev Increasing debt is prohibited if it was previously updated in the same block
    /// @dev The resulting debt amount must be within allowed range
    /// @dev Increasing debt is prohibited if there are forbidden tokens enabled as collateral on the account
    /// @dev After debt increase, total amount borrowed by the credit manager in the current block must not exceed
    ///      the limit defined in the facade
    function increaseDebt(uint256 amount) external;

    /// @notice Decreases account's debt
    /// @param amount Underlying amount to repay, value above account's total debt indicates full repayment
    /// @dev Decreasing debt is prohibited when opening an account
    /// @dev Decreasing debt is prohibited if it was previously updated in the same block
    /// @dev The resulting debt amount must be within allowed range or zero
    /// @dev Full repayment brings account into a special mode that skips collateral checks and thus requires
    ///      an account to have no potential debt sources, e.g., all quotas must be disabled
    function decreaseDebt(uint256 amount) external;

    /// @notice Updates account's quota for a token
    /// @param token Token to update the quota for
    /// @param quotaChange Desired quota change in underlying token units (`type(int96).min` to disable quota)
    /// @param minQuota Minimum resulting account's quota for token required not to revert
    /// @dev Enables token as collateral if quota is increased from zero, disables if decreased to zero
    /// @dev Quota increase is prohibited if there are forbidden tokens enabled as collateral on the account
    /// @dev Quota update is prohibited if account has zero debt
    /// @dev Resulting account's quota for token must not exceed the limit defined in the facade
    function updateQuota(address token, int96 quotaChange, uint96 minQuota) external;

    /// @notice Withdraws collateral from account
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw, `type(uint256).max` to withdraw all balance
    /// @param to Token recipient
    /// @dev This method can also be called during liquidation
    /// @dev Withdrawals are prohibited in multicalls if there are forbidden tokens enabled as collateral on the account
    /// @dev Withdrawals activate safe pricing (min of main and reserve feeds) in collateral check
    function withdrawCollateral(address token, uint256 amount, address to) external;

    /// @notice Sets advanced collateral check parameters
    /// @param collateralHints Optional array of token masks to check first to reduce the amount of computation
    ///        when known subset of account's collateral tokens covers all the debt
    /// @param minHealthFactor Min account's health factor in bps in order not to revert, must be at least 10000
    function setFullCheckParams(uint256[] calldata collateralHints, uint16 minHealthFactor) external;

    /// @notice Enables token as account's collateral, which makes it count towards account's total value
    /// @param token Token to enable as collateral
    /// @dev Enabling forbidden tokens is prohibited
    /// @dev Quoted tokens can only be enabled via `updateQuota`, this method is no-op for them
    function enableToken(address token) external;

    /// @notice Disables token as account's collateral
    /// @param token Token to disable as collateral
    /// @dev Quoted tokens can only be disabled via `updateQuota`, this method is no-op for them
    function disableToken(address token) external;

    /// @notice Revokes account's allowances for specified spender/token pairs
    /// @param revocations Array of spender/token pairs
    /// @dev Exists primarily to allow users to revoke allowances on accounts from old account factory on mainnet
    function revokeAdapterAllowances(RevocationPair[] calldata revocations) external;
}

interface ICreditManagerV3 {
    function calcTotalValue(address creditAccount) external view returns (uint256 total, uint256 twv);

    function calcDebtAndCollateral(address creditAccount, CollateralCalcTask task)
        external
        view
        returns (CollateralDebtData memory cdd);

    function calcCreditAccountHealthFactor(address creditAccount) external view returns (uint256 hf); // health factory of 1 means liquiditation

    function creditAccountInfo(address creditAccount)
        external
        view
        returns (
            uint256 debt,
            uint256 cumulativeIndexLastUpdate,
            uint128 cumulativeQuotaInterest,
            uint128 quotaFees,
            uint256 enabledTokensMask,
            uint16 flags,
            uint64 lastDebtUpdate,
            address borrower
        );
}
