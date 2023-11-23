pragma solidity 0.8.19;
/// @dev 0.8.20 set's the default EVM version to shanghai and uses push0. That's not supported on L2s

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IAdapter} from "../interfaces/vault/IAdapter.sol";

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
    IAdapter public immutable strategy;

    uint public immutable decimals;
    uint public immutable MAX_LOCK_TIME;
    address public constant PROTOCOL_FEE_RECIPIENT = 0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E;
    uint public constant PROTOCOL_FEE = 10;
    
    uint protocolFees;
    
    mapping(address => Lock) public locks;
    mapping(address => uint) public accruedRewards;
    mapping(address => mapping(address => bool)) public approvals;
    uint public totalSupply;
    uint public currIndex;

    event LockCreated(address indexed user, uint amount, uint lockTime);
    event Withdrawal(address indexed user, uint amount);
    event IncreaseLockTime(address indexed user, uint newLockTime);
    event IncreaseLockAmount(address indexed user, uint amount);
    event Claimed(address indexed user, uint amount);
    event DistributeRewards(address indexed distributor, uint amount);

    constructor(address _asset, uint _maxLockTime, address _rewardToken, address _strategy) {
        asset = ERC20(_asset);
        MAX_LOCK_TIME = _maxLockTime;
        decimals = ERC20(_asset).decimals();

        rewardToken = ERC20(_rewardToken);

        strategy = IAdapter(_strategy);
        ERC20(_asset).approve(_strategy, type(uint).max);
    }

    function deposit(address recipient, uint amount, uint lockTime) external returns (uint shares){
        require(locks[recipient].unlockTime == 0, "LOCK_EXISTS");

        shares = toShares(amount, lockTime);
        require(shares != 0, "NO_SHARES");

        totalSupply += shares;
        locks[recipient] = Lock({
            unlockTime: block.timestamp + lockTime,
            rewardIndex: currIndex,
            amount: amount,
            shares: shares
        });

        asset.safeTransferFrom(msg.sender, address(this), amount);

        strategy.deposit(amount, address(this));

        emit LockCreated(recipient, amount, lockTime);
    }

    function withdraw(address owner, address recipient) external {
        _isApproved(owner);

        uint shares = locks[owner].shares;
        require(shares != 0, "NO_LOCK");
        require(block.timestamp > locks[owner].unlockTime, "LOCKED");

        accrueUser(owner);
        uint amount = shares.mulDivDown(strategy.totalAssets(), totalSupply);

        totalSupply -= shares;
        delete locks[owner];

        strategy.withdraw(amount, recipient, address(this));
    
        emit Withdrawal(owner, amount);
    }

    function increaseLockTime(address owner, uint newLockTime) external {
        _isApproved(owner);

        accrueUser(owner);

        uint amount = locks[owner].amount;
        require(amount != 0, "NO_LOCK");
        require(newLockTime + block.timestamp > locks[owner].unlockTime, "INCREASE_LOCK_TIME");

        uint newShares = toShares(locks[owner].amount, newLockTime);

        totalSupply = totalSupply - locks[owner].shares + newShares;
        locks[owner].unlockTime = block.timestamp + newLockTime;
        locks[owner].shares = newShares;
    
        emit IncreaseLockTime(owner, newLockTime);
    }

    function increaseLockAmount(address owner, uint amount) external {
        _isApproved(owner);

        accrueUser(owner);

        uint currAmount = locks[owner].amount;
        require(currAmount != 0, "NO_LOCK");

        uint newShares = toShares(amount, locks[owner].unlockTime - block.timestamp);

        totalSupply = totalSupply + newShares;
        locks[owner].amount = currAmount + amount;
        locks[owner].shares += newShares;

        asset.safeTransferFrom(msg.sender, address(this), amount);

        strategy.deposit(amount, address(this));
    
        emit IncreaseLockAmount(owner, amount);
    }

    function toShares(uint amount, uint lockTime) public view returns (uint) {
        require(lockTime <= MAX_LOCK_TIME, "LOCK_TIME");
        uint totalAssets = strategy.totalAssets();
        uint shares;
        if (totalAssets == 0) {
            shares = amount;
        } else {
            shares = amount.mulDivDown(totalSupply, strategy.totalAssets());
        }
        return shares.mulDivDown(lockTime, MAX_LOCK_TIME);
    }

    function distributeRewards(uint amount) external {
        uint fee = amount * PROTOCOL_FEE / 10_000;
        protocolFees += fee;

        // amount of reward tokens that will be distributed per share
        uint delta = (amount - fee).mulDivDown(10 ** decimals, totalSupply);
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

    function approve(address spender, bool value) external {
        approvals[msg.sender][spender] = value;
    }

    function claimProtocolFees() external {
        uint amount = protocolFees;
        protocolFees = 0;
        rewardToken.safeTransfer(PROTOCOL_FEE_RECIPIENT, amount);
    }

    function _isApproved(address user) internal {
        require(user == msg.sender || approvals[user][msg.sender] == true, "UNAUTHORIZED");
    }
}