pragma solidity 0.8.19;
/// @dev 0.8.20 set's the default EVM version to shanghai and uses push0. That's not supported on L2s

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IERC4626} from "../interfaces/vault/IAdapter.sol";

struct Lock {
    uint128 lockTime;
    uint128 unlockTime;
    uint256 rewardIndex;
    uint256 amount;
    uint256 rewardShares;
}

contract StakingVault is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    ERC20 public immutable asset;
    ERC20 public immutable rewardToken;
    IERC4626 public immutable strategy;

    uint256 public immutable MAX_LOCK_TIME;
    address public constant PROTOCOL_FEE_RECIPIENT =
        0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E;
    uint256 public constant PROTOCOL_FEE = 10;

    uint256 protocolFees;

    mapping(address => Lock) public locks;
    mapping(address => uint256) public accruedRewards;

    uint256 public totalRewardSupply;
    uint256 public currIndex;

    uint256 internal toShareDivider = 1;

    event LockCreated(address indexed user, uint256 amount, uint256 lockTime);
    event Withdrawal(address indexed user, uint256 amount);
    event IncreaseLockTime(address indexed user, uint256 newLockTime);
    event IncreaseLockAmount(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event DistributeRewards(address indexed distributor, uint256 amount);

    constructor(
        address _asset,
        uint256 _maxLockTime,
        address _rewardToken,
        address _strategy,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, ERC20(_asset).decimals()) {
        asset = ERC20(_asset);
        MAX_LOCK_TIME = _maxLockTime;

        rewardToken = ERC20(_rewardToken);

        strategy = IERC4626(_strategy);

        uint8 stratDecimals = strategy.decimals();
        if (stratDecimals > 18) toShareDivider = 10 ** (stratDecimals - 18);

        ERC20(_asset).approve(_strategy, type(uint256).max);
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
        return strategy.previewDeposit(amount) / toShareDivider;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT / WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function deposit(
        address recipient,
        uint256 amount,
        uint256 lockTime
    ) external returns (uint256 shares) {
        require(locks[recipient].unlockTime == 0, "LOCK_EXISTS");

        uint256 rewardShares;
        (shares, rewardShares) = _getShares(amount, lockTime);

        asset.safeTransferFrom(msg.sender, address(this), amount);

        strategy.deposit(amount, address(this));

        _mint(recipient, shares);

        locks[recipient] = Lock({
            lockTime: uint128(block.timestamp),
            unlockTime: uint128(block.timestamp + lockTime),
            rewardIndex: currIndex,
            amount: amount,
            rewardShares: rewardShares
        });

        totalRewardSupply += rewardShares;

        emit LockCreated(recipient, amount, lockTime);
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

        amount = shares.mulDivDown(
            strategy.balanceOf(address(this)),
            totalSupply
        );

        _burn(owner, shares);

        totalRewardSupply -= locks[owner].rewardShares;

        delete locks[owner];

        strategy.redeem(amount, recipient, address(this));

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

        strategy.deposit(amount, address(this));

        _mint(recipient, shares);

        locks[recipient].amount += amount;
        locks[recipient].rewardShares += newRewardShares;

        totalRewardSupply += newRewardShares;

        emit IncreaseLockAmount(recipient, amount);
    }

    function increaseLockTime(uint256 newLockTime) external {
        accrueUser(msg.sender);

        uint256 amount = locks[msg.sender].amount;
        require(amount != 0, "NO_LOCK");
        require(
            newLockTime + block.timestamp > locks[msg.sender].unlockTime,
            "INCREASE_LOCK_TIME"
        );

        uint256 timeLeft = (block.timestamp - locks[msg.sender].lockTime);

        uint256 newRewardShares = toRewardShares(
            locks[msg.sender].amount,
            timeLeft + newLockTime
        );

        totalRewardSupply += (newRewardShares - locks[msg.sender].rewardShares);

        locks[msg.sender].lockTime = uint128(block.timestamp);
        locks[msg.sender].unlockTime = uint128(block.timestamp + newLockTime);
        locks[msg.sender].rewardShares = newRewardShares;

        emit IncreaseLockTime(msg.sender, newLockTime);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    function distributeRewards(uint256 amount) external {
        uint256 fee = (amount * PROTOCOL_FEE) / 10_000;
        protocolFees += fee;

        // amount of reward tokens that will be distributed per share
        uint256 delta = (amount - fee).mulDivDown(
            10 ** decimals,
            totalRewardSupply
        );

        /// @dev if delta == 0, no one will receive any rewards.
        require(delta != 0, "LOW_AMOUNT");

        currIndex += delta;

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        emit DistributeRewards(msg.sender, amount);
    }

    function accrueUser(address user) public {
        uint256 rewardShares = locks[user].rewardShares;
        if (rewardShares == 0) return;

        uint256 userIndex = locks[user].rewardIndex;

        uint256 delta = currIndex - userIndex;

        locks[user].rewardIndex = currIndex;
        accruedRewards[user] += (rewardShares * delta) / (10 ** decimals);
    }

    function claim(address user) external {
        accrueUser(user);

        uint256 rewards = accruedRewards[user];
        require(rewards != 0, "NO_REWARDS");

        accruedRewards[user] = 0;

        rewardToken.safeTransfer(user, rewards);

        emit Claimed(msg.sender, rewards);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    function claimProtocolFees() external {
        uint256 amount = protocolFees;

        delete protocolFees;

        rewardToken.safeTransfer(PROTOCOL_FEE_RECIPIENT, amount);
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
