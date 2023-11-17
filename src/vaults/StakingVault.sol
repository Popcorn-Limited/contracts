pragma solidity 0.8.19;
/// @dev 0.8.20 set's the default EVM version to shanghai and uses push0. That's not supported on L2s

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

struct Lock {
    uint unlockTime;
    uint rewardIndex;
    uint amount;
    uint shares;
}

contract StakingVault {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    ERC20 public immutable asset;
    ERC20 public immutable rewardToken;
    uint public immutable decimals;
    uint public immutable MAX_LOCK_TIME;
    
    mapping(address => Lock) public locks;
    mapping(address => uint) public accruedRewards;
    uint public totalSupply;
    uint public currIndex;

    event LockCreated(address indexed user, uint amount, uint lockTime);
    event Withdrawal(address indexed user, uint amount);
    event IncreaseLockTime(address indexed user, uint newLockTime);
    event IncreaseLockAmount(address indexed user, uint amount);
    event Claimed(address indexed user, uint amount);
    event DistributeRewards(address indexed distributor, uint amount);

    constructor(address _asset, uint _maxLockTime, address _rewardToken) {
        asset = ERC20(_asset);
        MAX_LOCK_TIME = _maxLockTime;
        decimals = ERC20(_asset).decimals();

        rewardToken = ERC20(_rewardToken);
    }

    function deposit(uint amount, uint lockTime) external returns (uint shares){
        require(locks[msg.sender].unlockTime == 0, "LOCK_EXISTS");

        shares = toShares(amount, lockTime);
        require(shares != 0, "NO_SHARES");

        totalSupply += shares;
        locks[msg.sender] = Lock({
            unlockTime: block.timestamp + lockTime,
            rewardIndex: currIndex,
            amount: amount,
            shares: shares
        });

        asset.safeTransferFrom(msg.sender, address(this), amount);

        emit LockCreated(msg.sender, amount, lockTime);
    }

    function withdraw() external {
        accrueUser(msg.sender);
        require(block.timestamp > locks[msg.sender].unlockTime, "LOCKED");

        totalSupply -= locks[msg.sender].shares;
        uint amount = locks[msg.sender].amount;
        delete locks[msg.sender];

        asset.safeTransfer(msg.sender, amount);
    
        emit Withdrawal(msg.sender, amount);
    }

    function increaseLockTime(uint newLockTime) external {
        accrueUser(msg.sender);

        uint amount = locks[msg.sender].amount;
        require(amount != 0, "NO_LOCK");
        require(newLockTime > locks[msg.sender].unlockTime, "INCREASE_LOCK_TIME");

        uint newShares = toShares(locks[msg.sender].amount, newLockTime);

        totalSupply = totalSupply - locks[msg.sender].shares + newShares;
        locks[msg.sender].unlockTime = block.timestamp + newLockTime;
        locks[msg.sender].shares = newShares;
    
        emit IncreaseLockTime(msg.sender, newLockTime);
    }

    function increaseLockAmount(uint amount) external {
        accrueUser(msg.sender);

        uint currAmount = locks[msg.sender].amount;
        require(currAmount != 0, "NO_LOCK");

        uint newShares = toShares(currAmount + amount, locks[msg.sender].unlockTime - block.timestamp);

        totalSupply = totalSupply - locks[msg.sender].shares + newShares;
        locks[msg.sender].amount = currAmount + amount;
        locks[msg.sender].shares = newShares;

        asset.safeTransferFrom(msg.sender, address(this), amount);
    
        emit IncreaseLockAmount(msg.sender, amount);
    }

    function toShares(uint amount, uint lockTime) public view returns (uint) {
        require(lockTime <= MAX_LOCK_TIME, "LOCK_TIME");
        return amount.mulDivDown(lockTime, MAX_LOCK_TIME);
    }

    function distributeRewards(uint amount) external {
        // amount of reward tokens that will be distributed per share
        uint delta = amount.mulDivDown(10 ** decimals, totalSupply);
        /// @dev if delta == 0, no one will receive any rewards.
        require(delta != 0, "LOW_AMOUNT") ;
        currIndex += delta;
    
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    
        emit DistributeRewards(msg.sender, amount);
    }

    function accrueUser(address user) public {
        uint shares = locks[user].shares;
        if (shares == 0) return;

        uint userIndex = locks[user].rewardIndex;

        uint delta = currIndex - userIndex;

        locks[user].rewardIndex = currIndex;
        accruedRewards[user] += shares * delta / (10 ** decimals);
    }

    function claim(address user) external {
        accrueUser(user);

        uint rewards = accruedRewards[user];
        require(rewards != 0, "NO_REWARDS");

        accruedRewards[user] = 0;

        rewardToken.safeTransfer(user, rewards);

        emit Claimed(msg.sender, rewards);
    }
}