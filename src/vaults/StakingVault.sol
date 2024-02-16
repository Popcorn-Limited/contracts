pragma solidity >=0.8.0;
/// @dev 0.8.20 set's the default EVM version to shanghai and uses push0. That's not supported on L2s

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IERC4626} from "../interfaces/vault/IAdapter.sol";

struct Lock {
    uint256 unlockTime;
    uint256 amount;
    uint256 rewardShares;
}

contract StakingVault is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 public immutable asset;

    IERC4626 public strategy;
    ERC20[] public rewardTokens;

    uint256 public immutable MAX_LOCK_TIME;
    address public constant PROTOCOL_FEE_RECIPIENT =
        0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E;
    uint256 public constant PROTOCOL_FEE = 10;

    uint256[] public protocolFees;

    mapping(address => Lock) public locks;
    mapping(address => uint256[]) public accruedRewards;
    mapping(address => uint256[]) public rewardIndices;

    uint256 public totalRewardSupply;
    uint256[] public currIndices;

    uint256 internal toShareDivider = 1;

    event LockCreated(address indexed user, uint256 amount, uint256 lockTime);
    event Withdrawal(address indexed user, uint256 amount);
    event IncreaseLockTime(address indexed user, uint256 newLockTime);
    event IncreaseLockAmount(address indexed user, uint256 amount);
    event Claimed(address indexed user, ERC20 rewardToken, uint256 amount);
    event DistributeRewards(
        address indexed distributor,
        ERC20 rewardToken,
        uint256 amount
    );

    constructor(
        address _asset,
        address[] memory _rewardTokens,
        address _strategy,
        uint256 _maxLockTime,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, ERC20(_asset).decimals()) {
        uint256 len = _rewardTokens.length;

        require(len > 0, "REWARD_TOKENS");
        require(_asset != address(0), "ASSET");
        require(_maxLockTime > 0, "MAX_LOCK_TIME");

        asset = ERC20(_asset);
        MAX_LOCK_TIME = _maxLockTime;

        for (uint256 i; i < len; i++) {
            require(_rewardTokens[i] != address(0), "REWARD");
            rewardTokens.push(ERC20(_rewardTokens[i]));
            currIndices.push(0);
            protocolFees.push(0);
        }

        if (_strategy != address(0)) {
            strategy = IERC4626(_strategy);

            uint256 stratDecimals = strategy.decimals();
            if (stratDecimals > 18) toShareDivider = 10 ** (stratDecimals - 18);

            ERC20(_asset).approve(_strategy, type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    function getRewardLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function getRewardTokens() external view returns (ERC20[] memory) {
        return rewardTokens;
    }

    function getCurrIndices() external view returns (uint256[] memory) {
        return currIndices;
    }

    function getUserIndices(
        address user
    ) external view returns (uint256[] memory) {
        return rewardIndices[user];
    }

    function getAccruedRewards(
        address user
    ) external view returns (uint256[] memory) {
        return accruedRewards[user];
    }

    function getProtocolFees() external view returns (uint256[] memory) {
        return protocolFees;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function toRewardShares(
        uint256 amount,
        uint256 lockTime
    ) public view returns (uint256) {
        require(lockTime <= MAX_LOCK_TIME, "LOCK_TIME");
        return amount.mulDivDown(lockTime, MAX_LOCK_TIME);
    }

    function toShares(uint256 amount) public view returns (uint256) {
        return
            address(strategy) == address(0)
                ? amount
                : strategy.previewDeposit(amount) / toShareDivider;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT / WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function deposit(
        address recipient,
        uint256 amount,
        uint256 lockTime
    ) external returns (uint256) {
        require(locks[recipient].unlockTime == 0, "LOCK_EXISTS");

        (uint256 shares, uint256 rewardShares) = _getShares(amount, lockTime);

        asset.safeTransferFrom(msg.sender, address(this), amount);

        if (address(strategy) != address(0))
            strategy.deposit(amount, address(this));

        _mint(recipient, shares);

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            rewardIndices[recipient].push(currIndices[i]);
            accruedRewards[recipient].push(0);
        }

        locks[recipient] = Lock({
            unlockTime: block.timestamp + lockTime,
            amount: amount,
            rewardShares: rewardShares
        });

        totalRewardSupply += rewardShares;

        emit LockCreated(recipient, amount, lockTime);

        return shares;
    }

    function withdraw(
        address owner,
        address recipient
    ) external returns (uint256 amount) {
        uint256 shares = balanceOf[owner];

        require(shares != 0, "NO_LOCK");
        require(block.timestamp > locks[owner].unlockTime, "LOCKED");

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        accrueUser(owner);
        _claim(owner);

        uint256 _totalSupply = totalSupply;
        _burn(owner, shares);

        totalRewardSupply -= locks[owner].rewardShares;

        delete locks[owner];
        delete rewardIndices[owner];

        if (address(strategy) != address(0)) {
            amount = shares.mulDivDown(
                strategy.balanceOf(address(this)),
                _totalSupply
            );
            strategy.redeem(amount, recipient, address(this));
        } else {
            amount = shares;
            asset.transfer(recipient, amount);
        }
        emit Withdrawal(owner, amount);
    }

    function _getShares(
        uint256 amount,
        uint256 lockTime
    ) internal returns (uint256 shares, uint256 rewardShares) {
        shares = toShares(amount);
        rewardShares = toRewardShares(amount, lockTime);
        require(shares > 0 && rewardShares > 0, "NO_SHARES");
    }

    /*//////////////////////////////////////////////////////////////
                            LOCK MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function increaseLockAmount(address recipient, uint256 amount) external {
        accrueUser(recipient);

        uint256 currAmount = locks[recipient].amount;
        require(currAmount != 0, "NO_LOCK");

        (uint256 shares, uint256 newRewardShares) = _getShares(
            amount,
            locks[recipient].unlockTime - block.timestamp
        );

        asset.safeTransferFrom(msg.sender, address(this), amount);

        if (address(strategy) != address(0))
            strategy.deposit(amount, address(this));

        _mint(recipient, shares);

        locks[recipient].amount += amount;
        locks[recipient].rewardShares += newRewardShares;

        totalRewardSupply += newRewardShares;

        emit IncreaseLockAmount(recipient, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    function distributeRewards(uint256[] calldata amounts) external {
        uint256 len = amounts.length;
        require(len == rewardTokens.length, "WRONG_AMOUNTS");

        uint256 totalDelta;

        for (uint256 i; i < len; i++) {
            uint256 fee = (amounts[i] * PROTOCOL_FEE) / 10_000;
            protocolFees[i] += fee;

            // amount of reward tokens that will be distributed per share
            uint256 delta = (amounts[i] - fee).mulDivDown(
                10 ** decimals,
                totalRewardSupply
            );

            if (delta > 0) {
                ERC20(rewardTokens[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    amounts[i]
                );

                currIndices[i] += delta;
                totalDelta += delta;

                emit DistributeRewards(msg.sender, rewardTokens[i], amounts[i]);
            }
        }

        /// @dev if totalDelta == 0, no one will receive any rewards.
        require(totalDelta > 0, "LOW_AMOUNT");
    }

    function accrueUser(address user) public {
        uint256 rewardShares = locks[user].rewardShares;
        if (rewardShares == 0) return;

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            uint256 delta = currIndices[i] - rewardIndices[user][i];

            rewardIndices[user][i] = currIndices[i];

            accruedRewards[user][i] +=
                (rewardShares * delta) /
                (10 ** decimals);
        }
    }

    function claim(address user) external {
        accrueUser(user);
        _claim(user);
    }

    function _claim(address user) internal {
        uint256[] memory rewards = accruedRewards[user];

        uint256 len = rewardTokens.length;
        for (uint256 i; i < len; i++) {
            uint256 reward = rewards[i];
            delete accruedRewards[user][i];

            if (reward > 0) {
                rewardTokens[i].safeTransfer(user, reward);
                emit Claimed(msg.sender, rewardTokens[i], reward);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    function claimProtocolFees() external {
        uint256[] memory fees = protocolFees;

        delete protocolFees;

        uint256 len = fees.length;
        for (uint256 i; i < len; i++) {
            uint256 fee = fees[i];
            if (fee > 0)
                rewardTokens[i].safeTransfer(PROTOCOL_FEE_RECIPIENT, fee);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function transfer(
        address to,
        uint256 value
    ) public override returns (bool) {
        revert("NO TRANSFER");
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        revert("NO TRANSFER");
    }
}
