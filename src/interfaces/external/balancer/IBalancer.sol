// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

enum SwapKind {
    GIVEN_IN,
    GIVEN_OUT
}

enum UserBalanceOpKind { 
    DEPOSIT_INTERNAL, 
    WITHDRAW_INTERNAL, 
    TRANSFER_INTERNAL, 
    TRANSFER_EXTERNAL 
}

interface IAsset {}

struct SingleSwap {
    bytes32 poolId;
    SwapKind kind;
    address assetIn;
    address assetOut;
    uint256 amount;
    bytes userData;
}

struct BatchSwapStep {
    bytes32 poolId;
    uint256 assetInIndex;
    uint256 assetOutIndex;
    uint256 amount;
    bytes userData;
}

struct FundManagement {
    address sender;
    bool fromInternalBalance;
    address payable recipient;
    bool toInternalBalance;
}

struct JoinPoolRequest {
    address[] assets;
    uint256[] maxAmountsIn;
    bytes userData;
    bool fromInternalBalance;
}

struct ExitPoolRequest {
    address[] assets;
    uint256[] minAmountsOut;
    bytes userData;
    bool toInternalBalance;
}

struct UserBalanceOp {
    UserBalanceOpKind kind;
    IAsset asset;
    uint256 amount;
    address sender;
    address payable recipient;
}

// Deployed at 0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5 on all chains.
interface IBalancerQueries {
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
}

interface IBalancerVault {
    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        IAsset[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external returns (int256[] memory assetDeltas);

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    function getPool(bytes32 poolId) external view returns (address lpToken, uint8 numTokens);

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request)
        external
        payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external;

    /**
     * @dev Performs a set of user balance operations, which involve Internal Balance (deposit, withdraw or transfer)
     * and plain ERC20 transfers using the Vault's allowance. This last feature is particularly useful for relayers, as
     * it lets integrators reuse a user's Vault allowance.
     *
     * For each operation, if the caller is not `sender`, it must be an authorized relayer for them.
     */
    function manageUserBalance(UserBalanceOp[] memory ops) external payable;
}

interface IBalancerRouter {
    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        returns (uint256 amountCalculated);
}

interface IPool {
    function getVault() external view returns (address balancerVault);
}

interface IGauge {
    function lp_token() external view returns (address);

    function bal_token() external view returns (address);

    function is_killed() external view returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function withdraw(uint256 amount, bool _claim_rewards) external;

    function deposit(uint256 amount) external;
}

interface IMinter {
    function mint(address gauge) external;

    function getBalancerToken() external view returns (address);

    function getGaugeController() external view returns (address);
}

interface IController {
    function gauge_exists(address _gauge) external view returns (bool);
}
