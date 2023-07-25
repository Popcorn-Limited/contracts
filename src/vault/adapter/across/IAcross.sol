// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Concise list of functions in HubPool implementation.
 */
interface IAcrossHop {
    // Each whitelisted L1 token has an associated pooledToken struct that contains all information used to track the
    // cumulative LP positions and if this token is enabled for deposits.
    struct PooledToken {
        // LP token given to LPs of a specific L1 token.
        address lpToken;
        // True if accepting new LP's.
        bool isEnabled;
        // Timestamp of last LP fee update.
        uint32 lastLpFeeUpdate;
        // Number of LP funds sent via pool rebalances to SpokePools and are expected to be sent
        // back later.
        int256 utilizedReserves;
        // Number of LP funds held in contract less utilized reserves.
        uint256 liquidReserves;
        // Number of LP funds reserved to pay out to LPs as fees.
        uint256 undistributedLpFees;
    }

    // A data worker can optimistically store several merkle roots on this contract by staking a bond and calling
    // proposeRootBundle. By staking a bond, the data worker is alleging that the merkle roots all contain valid leaves
    // that can be executed later to:
    // - Send funds from this contract to a SpokePool or vice versa
    // - Send funds from a SpokePool to Relayer as a refund for a relayed deposit
    // - Send funds from a SpokePool to a deposit recipient to fulfill a "slow" relay
    // Anyone can dispute this struct if the merkle roots contain invalid leaves before the
    // challengePeriodEndTimestamp. Once the expiration timestamp is passed, executeRootBundle to execute a leaf
    // from the poolRebalanceRoot on this contract and it will simultaneously publish the relayerRefundRoot and
    // slowRelayRoot to a SpokePool. The latter two roots, once published to the SpokePool, contain
    // leaves that can be executed on the SpokePool to pay relayers or recipients.

    struct RootBundle {
        // Contains leaves instructing this contract to send funds to SpokePools.
        bytes32 poolRebalanceRoot;
        // Relayer refund merkle root to be published to a SpokePool.
        bytes32 relayerRefundRoot;
        // Slow relay merkle root to be published to a SpokePool.
        bytes32 slowRelayRoot;
        // This is a 1D bitmap, with max size of 256 elements, limiting us to 256 chainsIds.
        uint256 claimedBitMap;
        // Proposer of this root bundle.
        address proposer;
        // Number of pool rebalance leaves to execute in the poolRebalanceRoot. After this number
        // of leaves are executed, a new root bundle can be proposed
        uint8 unclaimedPoolRebalanceLeafCount;
        // When root bundle challenge period passes and this root bundle becomes executable.
        uint32 challengePeriodEndTimestamp;
    }

    function addLiquidity(
        address l1Token,
        uint256 l1TokenAmount
    ) external payable;

    function removeLiquidity(
        address l1Token,
        uint256 lpTokenAmount,
        bool sendEth
    ) external;

    function pooledTokens(
        address l1Token
    ) external view returns (PooledToken memory);

    function rootBundleProposal() external view returns (RootBundle memory);

    function bondToken() external view returns (IERC20);

    // Interest rate payment that scales the amount of pending fees per second paid to LPs. 0.0000015e18 will pay out
    // the full amount of fees entitled to LPs in ~ 7.72 days assuming no contract interactions. If someone interacts
    // with the contract then the LP rewards are smeared sublinearly over the window (i.e spread over the remaining
    // period for each interaction which approximates a decreasing exponential function).
    function lpFeeRatePerSecond() external view returns (uint256);

    function bondAmount() external view returns (uint256);

    function getCurrentTime() external view returns (uint256);
}

interface IAcceleratingDistributor {
    // Each User deposit is tracked with the information below.
    struct UserDeposit {
        uint256 cumulativeBalance;
        uint256 averageDepositTime;
        uint256 rewardsAccumulatedPerToken;
        uint256 rewardsOutstanding;
    }

    /**
     * @notice Stake tokens for rewards.
     * @dev The caller of this function must approve this contract to spend amount of stakedToken.
     * @param stakedToken The address of the token to stake.
     * @param amount The amount of the token to stake.
     */
    function stake(address stakedToken, uint256 amount) external;

    /**
     * @notice Withdraw staked tokens.
     * @param stakedToken The address of the token to withdraw.
     * @param amount The amount of the token to withdraw.
     */
    function unstake(address stakedToken, uint256 amount) external;

    /**
     * @notice Returns all the information associated with a user's stake.
     * @param stakedToken The address of the staked token to query.
     * @param account The address of user to query.
     * @return UserDeposit Struct with: {cumulativeBalance,averageDepositTime,rewardsAccumulatedPerToken,rewardsOutstanding}
     */
    function getUserStake(
        address stakedToken,
        address account
    ) external view returns (UserDeposit memory);

    /**
     * @notice Get entitled rewards for the staker.
     * @dev Calling this method will reset the caller's reward multiplier.
     * @param stakedToken The address of the token to get rewards for.
     */
    function withdrawReward(address stakedToken) external;

    function rewardToken() external view returns (address);
}
