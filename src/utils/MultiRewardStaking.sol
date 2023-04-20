// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ERC4626Upgradeable, ERC20Upgradeable, IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {OwnedUpgradeable} from "./OwnedUpgradeable.sol";
import {IMultiRewardEscrow} from "../interfaces/IMultiRewardEscrow.sol";
import {RewardInfo, EscrowInfo} from "../interfaces/IMultiRewardStaking.sol";

/**
 * @title   MultiRewardStaking
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * An ERC4626 compliant implementation of a staking contract which allows rewards in multiple tokens.
 * Only one token can be staked but rewards can be added in any token.
 * Rewards can be paid out over time or instantly.
 * Only the owner can add new tokens as rewards. Once added they cant be removed or changed. RewardsSpeed can only be adjusted if the rewardsSpeed is not 0.
 * Anyone can fund existing rewards.
 * Based on the flywheel implementation of fei-protocol https://github.com/fei-protocol/flywheel-v2
 */
contract MultiRewardStaking is ERC4626Upgradeable, OwnedUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCastLib for uint256;
    using Math for uint256;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @notice Initialize a new MultiRewardStaking contract.
     * @param _stakingToken The token to be staked.
     * @param _escrow An optional escrow contract which can be used to lock rewards on claim.
     * @param _owner Owner of the contract. Controls management functions.
     */
    function initialize(
        IERC20 _stakingToken,
        IMultiRewardEscrow _escrow,
        address _owner
    ) external initializer {
        __ERC4626_init(IERC20Metadata(address(_stakingToken)));
        __Owned_init(_owner);

        _name = string(
            abi.encodePacked(
                "Staked ",
                IERC20Metadata(address(_stakingToken)).name()
            )
        );
        _symbol = string(
            abi.encodePacked(
                "pst-",
                IERC20Metadata(address(_stakingToken)).symbol()
            )
        );
        _decimals = IERC20Metadata(address(_stakingToken)).decimals();

        escrow = _escrow;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    function name()
        public
        view
        override(ERC20Upgradeable, IERC20Metadata)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(ERC20Upgradeable, IERC20Metadata)
        returns (string memory)
    {
        return _symbol;
    }

    function decimals()
        public
        view
        override(ERC20Upgradeable, IERC20Metadata)
        returns (uint8)
    {
        return _decimals;
    }

    /*//////////////////////////////////////////////////////////////
                    ERC4626 MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 _amount) external returns (uint256) {
        return deposit(_amount, msg.sender);
    }

    function mint(uint256 _amount) external returns (uint256) {
        return mint(_amount, msg.sender);
    }

    function withdraw(uint256 _amount) external returns (uint256) {
        return withdraw(_amount, msg.sender, msg.sender);
    }

    function redeem(uint256 _amount) external returns (uint256) {
        return redeem(_amount, msg.sender, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    error ZeroAddressTransfer(address from, address to);
    error InsufficentBalance();

    function _convertToShares(
        uint256 assets,
        Math.Rounding
    ) internal pure override returns (uint256) {
        return assets;
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding
    ) internal pure override returns (uint256) {
        return shares;
    }

    /// @notice Internal deposit function used by `deposit()` and `mint()`. Accrues rewards for the `caller` and `receiver`.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override accrueRewards(caller, receiver) {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /// @notice Internal withdraw function used by `withdraw()` and `redeem()`. Accrues rewards for the `caller` and `receiver`.
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override accrueRewards(owner, receiver) {
        if (caller != owner)
            _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Internal transfer function used by `transfer()` and `transferFrom()`. Accrues rewards for `from` and `to`.
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override accrueRewards(from, to) {
        if (from == address(0) || to == address(0))
            revert ZeroAddressTransfer(from, to);

        uint256 fromBalance = balanceOf(from);
        if (fromBalance < amount) revert InsufficentBalance();

        _burn(from, amount);
        _mint(to, amount);

        emit Transfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    IMultiRewardEscrow public escrow;

    event RewardsClaimed(
        address indexed user,
        IERC20 rewardToken,
        uint256 amount,
        bool escrowed
    );

    error ZeroRewards(IERC20 rewardToken);

    /**
     * @notice Claim rewards for a user in any amount of rewardTokens.
     * @param user User for which rewards should be claimed.
     * @param _rewardTokens Array of rewardTokens for which rewards should be claimed.
     * @dev This function will revert if any of the rewardTokens have zero rewards accrued.
     * @dev A percentage of each reward can be locked in an escrow contract if this was previously configured.
     */
    function claimRewards(
        address user,
        IERC20[] memory _rewardTokens
    ) external accrueRewards(msg.sender, user) {
        for (uint8 i; i < _rewardTokens.length; i++) {
            uint256 rewardAmount = accruedRewards[user][_rewardTokens[i]];

            if (rewardAmount == 0) revert ZeroRewards(_rewardTokens[i]);

            accruedRewards[user][_rewardTokens[i]] = 0;

            EscrowInfo memory escrowInfo = escrowInfos[_rewardTokens[i]];

            if (escrowInfo.escrowPercentage > 0) {
                _lockToken(user, _rewardTokens[i], rewardAmount, escrowInfo);
                emit RewardsClaimed(user, _rewardTokens[i], rewardAmount, true);
            } else {
                _rewardTokens[i].transfer(user, rewardAmount);
                emit RewardsClaimed(
                    user,
                    _rewardTokens[i],
                    rewardAmount,
                    false
                );
            }
        }
    }

    /// @notice Locks a percentage of a reward in an escrow contract. Pays out the rest to the user.
    function _lockToken(
        address user,
        IERC20 rewardToken,
        uint256 rewardAmount,
        EscrowInfo memory escrowInfo
    ) internal {
        uint256 escrowed = rewardAmount.mulDiv(
            uint256(escrowInfo.escrowPercentage),
            1e18,
            Math.Rounding.Down
        );
        uint256 payout = rewardAmount - escrowed;

        rewardToken.safeTransfer(user, payout);
        escrow.lock(
            rewardToken,
            user,
            escrowed,
            escrowInfo.escrowDuration,
            escrowInfo.offset
        );
    }

    /*//////////////////////////////////////////////////////////////
                    REWARDS MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    IERC20[] public rewardTokens;

    // rewardToken -> RewardInfo
    mapping(IERC20 => RewardInfo) public rewardInfos;
    // rewardToken -> EscrowInfo
    mapping(IERC20 => EscrowInfo) public escrowInfos;

    // user => rewardToken -> rewardsIndex
    mapping(address => mapping(IERC20 => uint256)) public userIndex;
    // user => rewardToken -> accruedRewards
    mapping(address => mapping(IERC20 => uint256)) public accruedRewards;

    event RewardInfoUpdate(
        IERC20 rewardToken,
        uint160 rewardsPerSecond,
        uint32 rewardsEndTimestamp
    );

    error RewardTokenAlreadyExist(IERC20 rewardToken);
    error RewardTokenDoesntExist(IERC20 rewardToken);
    error RewardTokenCantBeStakingToken();
    error ZeroAmount();
    error NotSubmitter(address submitter);
    error RewardsAreDynamic(IERC20 rewardToken);
    error ZeroRewardsSpeed();
    error InvalidConfig();

    /**
     * @notice Adds a new rewardToken which can be earned via staking. Caller must be owner.
     * @param rewardToken Token that can be earned by staking.
     * @param rewardsPerSecond The rate in which `rewardToken` will be accrued.
     * @param amount Initial funding amount for this reward.
     * @param useEscrow Bool if the rewards should be escrowed on claim.
     * @param escrowPercentage The percentage of the reward that gets escrowed in 1e18. (1e18 = 100%, 1e14 = 1 BPS)
     * @param escrowDuration The duration of the escrow.
     * @param offset A cliff after claim before the escrow starts.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev If `rewardsPerSecond` is 0 the rewards will be paid out instantly. In this case `amount` must be 0.
     * @dev If `useEscrow` is `false` the `escrowDuration`, `escrowPercentage` and `offset` will be ignored.
     * @dev The max amount of rewardTokens is 20.
     */
    function addRewardToken(
        IERC20 rewardToken,
        uint160 rewardsPerSecond,
        uint256 amount,
        bool useEscrow,
        uint192 escrowPercentage,
        uint32 escrowDuration,
        uint32 offset
    ) external onlyOwner {
        if (rewardTokens.length == 20) revert InvalidConfig();
        if (asset() == address(rewardToken))
            revert RewardTokenCantBeStakingToken();

        RewardInfo memory rewards = rewardInfos[rewardToken];
        if (rewards.lastUpdatedTimestamp > 0)
            revert RewardTokenAlreadyExist(rewardToken);

        if (amount > 0) {
            if (rewardsPerSecond == 0 && totalSupply() == 0)
                revert InvalidConfig();
            rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        }

        // Add the rewardToken to all existing rewardToken
        rewardTokens.push(rewardToken);

        if (useEscrow) {
            if (escrowPercentage == 0 || escrowPercentage > 1e18)
                revert InvalidConfig();
            escrowInfos[rewardToken] = EscrowInfo({
                escrowPercentage: escrowPercentage,
                escrowDuration: escrowDuration,
                offset: offset
            });
            rewardToken.safeApprove(address(escrow), type(uint256).max);
        }

        uint64 ONE = (10 ** IERC20Metadata(address(rewardToken)).decimals())
            .safeCastTo64();
        uint224 index = rewardsPerSecond == 0 && amount > 0
            ? ONE +
                amount
                    .mulDiv(
                        uint256(10 ** decimals()),
                        totalSupply(),
                        Math.Rounding.Down
                    )
                    .safeCastTo224()
            : ONE;
        uint32 rewardsEndTimestamp = rewardsPerSecond == 0
            ? block.timestamp.safeCastTo32()
            : _calcRewardsEnd(0, rewardsPerSecond, amount);

        rewardInfos[rewardToken] = RewardInfo({
            ONE: ONE,
            rewardsPerSecond: rewardsPerSecond,
            rewardsEndTimestamp: rewardsEndTimestamp,
            index: index,
            lastUpdatedTimestamp: block.timestamp.safeCastTo32()
        });

        emit RewardInfoUpdate(
            rewardToken,
            rewardsPerSecond,
            rewardsEndTimestamp
        );
    }

    /**
     * @notice Changes rewards speed for a rewardToken. This works only for rewards that accrue over time. Caller must be owner.
     * @param rewardToken Token that can be earned by staking.
     * @param rewardsPerSecond The rate in which `rewardToken` will be accrued.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     */
    function changeRewardSpeed(
        IERC20 rewardToken,
        uint160 rewardsPerSecond
    ) external onlyOwner {
        RewardInfo memory rewards = rewardInfos[rewardToken];

        if (rewardsPerSecond == 0) revert ZeroAmount();
        if (rewards.lastUpdatedTimestamp == 0)
            revert RewardTokenDoesntExist(rewardToken);
        if (rewards.rewardsPerSecond == 0)
            revert RewardsAreDynamic(rewardToken);

        _accrueRewards(rewardToken, _accrueStatic(rewards));

        uint256 prevEndTime = uint256(rewards.rewardsEndTimestamp);
        uint256 currTime = block.timestamp;
        uint256 remainder = prevEndTime <= currTime
            ? 0
            : uint256(rewards.rewardsPerSecond) * (prevEndTime - currTime);

        uint32 rewardsEndTimestamp = _calcRewardsEnd(
            currTime.safeCastTo32(),
            rewardsPerSecond,
            remainder
        );
        rewardInfos[rewardToken].rewardsPerSecond = rewardsPerSecond;
        rewardInfos[rewardToken].rewardsEndTimestamp = rewardsEndTimestamp;
    }

    /**
     * @notice Funds rewards for a rewardToken.
     * @param rewardToken Token that can be earned by staking.
     * @param amount The amount of rewardToken that will fund this reward.
     * @dev The `rewardsEndTimestamp` gets calculated based on `rewardsPerSecond` and `amount`.
     * @dev If `rewardsPerSecond` is 0 the rewards will be paid out instantly.
     */
    function fundReward(IERC20 rewardToken, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        // Cache RewardInfo
        RewardInfo memory rewards = rewardInfos[rewardToken];

        if (rewards.rewardsPerSecond == 0 && totalSupply() == 0)
            revert InvalidConfig();

        // Make sure that the reward exists
        if (rewards.lastUpdatedTimestamp == 0)
            revert RewardTokenDoesntExist(rewardToken);

        // Transfer additional rewardToken to fund rewards of this vault
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 accrued = rewards.rewardsPerSecond == 0
            ? amount
            : _accrueStatic(rewards);

        // Update the index of rewardInfo before updating the rewardInfo
        _accrueRewards(rewardToken, accrued);
        uint32 rewardsEndTimestamp = rewards.rewardsEndTimestamp;
        if (rewards.rewardsPerSecond > 0) {
            rewardsEndTimestamp = _calcRewardsEnd(
                rewards.rewardsEndTimestamp,
                rewards.rewardsPerSecond,
                amount
            );
            rewardInfos[rewardToken].rewardsEndTimestamp = rewardsEndTimestamp;
        }

        emit RewardInfoUpdate(
            rewardToken,
            rewards.rewardsPerSecond,
            rewardsEndTimestamp
        );
    }

    function _calcRewardsEnd(
        uint32 rewardsEndTimestamp,
        uint160 rewardsPerSecond,
        uint256 amount
    ) internal returns (uint32) {
        if (rewardsEndTimestamp > block.timestamp)
            amount +=
                uint256(rewardsPerSecond) *
                (rewardsEndTimestamp - block.timestamp);

        return
            (block.timestamp + (amount / uint256(rewardsPerSecond)))
                .safeCastTo32();
    }

    function getAllRewardsTokens() external view returns (IERC20[] memory) {
        return rewardTokens;
    }

    /*//////////////////////////////////////////////////////////////
                      REWARDS ACCRUAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Accrue rewards for up to 2 users for all available reward tokens.
    modifier accrueRewards(address _caller, address _receiver) {
        IERC20[] memory _rewardTokens = rewardTokens;
        for (uint8 i; i < _rewardTokens.length; i++) {
            IERC20 rewardToken = _rewardTokens[i];
            RewardInfo memory rewards = rewardInfos[rewardToken];

            if (rewards.rewardsPerSecond > 0)
                _accrueRewards(rewardToken, _accrueStatic(rewards));
            _accrueUser(_receiver, rewardToken);

            // If a deposit/withdraw operation gets called for another user we should accrue for both of them to avoid potential issues like in the Convex-Vulnerability
            if (_receiver != _caller) _accrueUser(_caller, rewardToken);
        }
        _;
    }

    /**
     * @notice Accrue rewards over time.
     * @dev Based on https://github.com/fei-protocol/flywheel-v2/blob/main/src/rewards/FlywheelStaticRewards.sol
     */
    function _accrueStatic(
        RewardInfo memory rewards
    ) internal view returns (uint256 accrued) {
        uint256 elapsed;
        if (rewards.rewardsEndTimestamp > block.timestamp) {
            elapsed = block.timestamp - rewards.lastUpdatedTimestamp;
        } else if (rewards.rewardsEndTimestamp > rewards.lastUpdatedTimestamp) {
            elapsed =
                rewards.rewardsEndTimestamp -
                rewards.lastUpdatedTimestamp;
        }

        accrued = uint256(rewards.rewardsPerSecond * elapsed);
    }

    /// @notice Accrue global rewards for a rewardToken
    function _accrueRewards(IERC20 _rewardToken, uint256 accrued) internal {
        uint256 supplyTokens = totalSupply();
        uint224 deltaIndex; // DeltaIndex is the amount of rewardsToken paid out per stakeToken
        if (supplyTokens != 0)
            deltaIndex = accrued
                .mulDiv(
                    uint256(10 ** decimals()),
                    supplyTokens,
                    Math.Rounding.Down
                )
                .safeCastTo224();
        // rewardDecimals * stakeDecimals / stakeDecimals = rewardDecimals
        // 1e18 * 1e6 / 10e6 = 0.1e18 | 1e6 * 1e18 / 10e18 = 0.1e6

        rewardInfos[_rewardToken].index += deltaIndex;
        rewardInfos[_rewardToken].lastUpdatedTimestamp = block
            .timestamp
            .safeCastTo32();
    }

    /// @notice Sync a user's rewards for a rewardToken with the global reward index for that token
    function _accrueUser(address _user, IERC20 _rewardToken) internal {
        RewardInfo memory rewards = rewardInfos[_rewardToken];

        uint256 oldIndex = userIndex[_user][_rewardToken];

        // If user hasn't yet accrued rewards, grant them interest from the strategy beginning if they have a balance
        // Zero balances will have no effect other than syncing to global index
        if (oldIndex == 0) {
            oldIndex = rewards.ONE;
        }

        uint256 deltaIndex = rewards.index - oldIndex;

        // Accumulate rewards by multiplying user tokens by rewardsPerToken index and adding on unclaimed
        uint256 supplierDelta = balanceOf(_user).mulDiv(
            deltaIndex,
            uint256(10 ** decimals()),
            Math.Rounding.Down
        );
        // stakeDecimals  * rewardDecimals / stakeDecimals = rewardDecimals
        // 1e18 * 1e6 / 10e18 = 0.1e18 | 1e6 * 1e18 / 10e18 = 0.1e6

        userIndex[_user][_rewardToken] = rewards.index;

        accruedRewards[_user][_rewardToken] += supplierDelta;
    }

    /*//////////////////////////////////////////////////////////////
                            PERMIT LOGC
    //////////////////////////////////////////////////////////////*/

    uint256 internal INITIAL_CHAIN_ID;
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    error PermitDeadlineExpired(uint256 deadline);
    error InvalidSigner(address signer);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (deadline < block.timestamp) revert PermitDeadlineExpired(deadline);

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0) || recoveredAddress != owner)
                revert InvalidSigner(recoveredAddress);

            _approve(recoveredAddress, spender, value);
        }
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name())),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }
}
