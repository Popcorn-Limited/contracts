// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {
    ERC4626Upgradeable,
    IERC20Upgradeable as IERC20,
    IERC20MetadataUpgradeable as IERC20Metadata,
    ERC20Upgradeable as ERC20
} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from
    "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import {EIP165} from "../../utils/EIP165.sol";
import {OwnedUpgradeable} from "../../utils/OwnedUpgradeable.sol";
import {VaultFees} from "../../interfaces/vault/IVault.sol";

struct VaultInitData {
    address asset;
    string name;
    string symbol;
    address owner;
    VaultFees fees;
    address feeRecipient;
    uint depositLimit;
    uint128 harvestCooldown;
    uint8 autoHarvest;
}

struct Strategy {
    address addr;
    uint96 weight;
}

interface IStrategy {
    function deposit(uint amount) external;
    function withdraw(address to, uint amount) external;
    function totalAssets() external view returns (uint);
}

/**
 * @title   baseVault
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
contract Vault is
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnedUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP165
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint8 internal _decimals;
    uint8 public constant decimalOffset = 9;
    uint8 public autoHarvest;
    uint128 harvestCooldown;
    uint128 lastHarvest;

    uint depositLimit;
    bytes32 contractName;

    Strategy[] strategies;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error StrategySetupFailed();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize a new Vault.
     * @dev `asset` - The underlying asset
     * @dev `_owner` - Owner of the contract. Controls management functions.
     * @dev `_strategy` - An optional strategy to enrich the adapter with additional functionality.
     * @dev `_harvestCooldown` - Cooldown period between harvests.
     * @dev `_requiredSigs` - Function signatures required by the strategy (EIP-165)
     * @dev `_strategyConfig` - Additional data which can be used by the strategy on `harvest()`
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Each Adapter implementation should implement checks to make sure that the adapter is wrapping the underlying protocol correctly.
     * @dev If a strategy is provided, it will be verified to make sure it implements the required functions.
     */
    function initialize(VaultInitData calldata initData) internal initializer {
        __Owned_init(initData.owner);
        __Pausable_init();
        __ERC4626_init(IERC20Metadata(initData.asset));

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        _decimals = IERC20Metadata(initData.asset).decimals() + decimalOffset; // Asset decimals + decimal offset to combat inflation attacks
        highWaterMark = 1e9;

        fees = initData.fees;
        feeRecipient = initData.feeRecipient;
    
        depositLimit = initData.depositLimit;

        // _name = initData.name;
        // _symbol = initData.symbol;

        contractName = keccak256(
            abi.encodePacked("Popcorn", initData.name, block.timestamp, "Vault")
        ); 

        quitPeriod = 3 days;

        lastHarvest = uint128(block.timestamp);
        autoHarvest = initData.autoHarvest;
        harvestCooldown = initData.harvestCooldown;

        emit VaultInitialized(contractName, address(initData.asset));
    }
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function updateStrategies(Strategy[] calldata _strategies) external onlyOwner {
        // it's easier to update the whole array instead of adding and removing individual strats

        _deallocate();

        delete strategies;

        for (uint i; i < _strategies.length;) {
            strategies.push(_strategies[i]);
            unchecked {++i;}
        }
    
        allocate();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    error MaxError(uint256 amount);
    error ZeroAmount();

    function deposit(uint assets, address receiver) public override nonReentrant whenNotPaused returns (uint shares) {
        if (assets > maxDeposit(receiver)) revert MaxError(assets);
    
        /// @dev Inititalize account for managementFee on first deposit
        if (totalSupply() == 0) feesUpdatedAt = block.timestamp;

        // TODO: are we ever going to use deposit fees? Removing them will reduce gas costs of the main user flow
        uint feeShares = _convertToShares(
            assets.mulDiv(uint256(fees.deposit), 1e18, Math.Rounding.Down),
            Math.Rounding.Down
        );

        shares = _convertToShares(assets, Math.Rounding.Down) - feeShares;
        if (shares == 0) revert ZeroAmount();

        if (feeShares > 0) _mint(feeRecipient, feeShares);

        _deposit(msg.sender, receiver, assets, shares); 
    }

    /**
     * @notice Mint exactly `shares` vault shares to `receiver`, taking the necessary amount of `asset` from the caller.
     * @param shares Quantity of shares to mint.
     * @param receiver Receiver of issued vault shares.
     * @return assets Quantity of assets deposited by caller.
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares > maxMint(receiver)) revert MaxError(assets);

        // Inititalize account for managementFee on first deposit
        if (totalSupply() == 0) feesUpdatedAt = block.timestamp;

        uint256 feeShares = shares.mulDiv(
            uint(fees.deposit),
            1e18 - uint(fees.deposit),
            Math.Rounding.Down
        );

        assets = _convertToAssets(shares + feeShares, Math.Rounding.Up);

        if (feeShares > 0) _mint(feeRecipient, feeShares);
    
        _deposit(msg.sender, receiver, assets, shares);
    }


    /**
     * @notice Deposit `assets` into the underlying protocol and mints vault shares to `receiver`.
     * @dev Executes harvest if `harvestCooldown` is passed since last invocation.
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);

        _mint(receiver, shares);

        _afterDeposit();

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Withdraws `assets` from the underlying protocol and burns vault shares from `owner`.
     * @dev Executes harvest if `harvestCooldown` is passed since last invocation.
     */
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }



        if (!paused()) {
            // TODO: need to implement a withdrawal queue to pull funds from the strategies.
            // See Tribe's contract for that
        }

        _burn(owner, shares);

        _withdrawFunds(receiver, assets);

        _afterWithdrawal();

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // shouldn't be called in case of a pause since we want to leave funds in the vault
    function allocate() public whenNotPaused {
        IERC20 asset = IERC20(asset());
        uint balance = asset.balanceOf(address(this));

        uint len = strategies.length;
        for (uint i; i < len;) {
            uint amount = 1e5 * balance / uint(strategies[i].weight);
            asset.safeTransfer(strategies[i].addr, amount);
            IStrategy(strategies[i].addr).deposit(amount);
            unchecked {++i;}
        }
    }

    function _deallocate() internal {
        uint len = strategies.length;
        for (uint i; i < len;) {
            IStrategy strat = IStrategy(strategies[i].addr);
            strat.withdraw(address(this), strat.totalAssets());
            unchecked {++i;}
        }
    }

    function _withdrawFunds(address to, uint amount) internal {
        IERC20 token = IERC20(asset());
        uint idleFunds = token.balanceOf(address(this));
        if (idleFunds < amount) {
            uint toPull = amount - idleFunds;

            uint len = strategies.length;
            for (uint i; i < len;) {
                IStrategy strat = IStrategy(strategies[i].addr);
                uint stratBal = strat.totalAssets();
                if (toPull > stratBal) {
                    // if the strat doesn't have enough funds, we pull everything it has
                    // and continue with the next strategy
                    strat.withdraw(to, stratBal);
                    toPull -= stratBal;
                } else {
                    strat.withdraw(to, toPull);
                    break;
                }
                unchecked {++i;}
            }
        }

        // we only send idle funds because the rest was already sent to the user by the strategy
        token.safeTransfer(to, idleFunds);
    }

    function _afterDeposit() internal {
        // TODO: add harvest stuff
    }

    function _afterWithdrawal() internal {

    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO: on pause we have to remove all funds from the strategies and put
    // them in the vault

    /**
     * @notice Total amount of underlying `asset` token managed by adapter.
     * @dev Return assets held by adapter if paused.
     */
    function totalAssets() public view override returns (uint256) {
        return paused() ? IERC20(asset()).balanceOf(address(this)) : _totalAssets();
    }

    /**
     * @notice Total amount of underlying `asset` token managed by adapter through the underlying protocol.
     */
    function _totalAssets() internal view returns (uint256 total) {
        // vault could hold funds that haven't been allocated yet
        total = IERC20(asset()).balanceOf(address(this));

        uint len = strategies.length;
        for (uint i; i < len;) {
            total += IStrategy(strategies[i].addr).totalAssets();
            unchecked {++i;}
        }
    }

    /**
     * @notice Convert either `assets` or `shares` into underlying shares.
     * @dev This is an optional function for underlying protocols that require deposit/withdrawal amounts in their shares.
     * @dev Returns shares if totalSupply is 0.
     */
    function convertToUnderlyingShares(uint256 assets, uint256 shares) public view virtual returns (uint256) {}

    /**
     * @notice Simulate the effects of a deposit at the current block, given current on-chain conditions.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return paused() ? 0 : _convertToShares(assets, Math.Rounding.Down);
    }

    /**
     * @notice Simulate the effects of a mint at the current block, given current on-chain conditions.
     * @dev Return 0 if paused since no further deposits are allowed.
     * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
     */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return paused() ? 0 : _convertToAssets(shares, Math.Rounding.Up);
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256 shares)
    {
        return assets.mulDiv(totalSupply() + 10 ** decimalOffset, totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        virtual
        override
        returns (uint256)
    {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** decimalOffset, rounding);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/


    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address. 
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        if (paused() || assets >= depositLimit_) return 0;
        return depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address. 
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        if (paused() || assets >= depositLimit_) return 0;
        return _convertToShares(depositLimit_ - assets, Math.Rounding.Down);
    }

    /*//////////////////////////////////////////////////////////////
                      FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;
    uint256 public highWaterMark;
    uint public feesUpdatedAt;

    address public constant FEE_RECIPIENT = address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);

    event PerformanceFeeChanged(uint256 oldFee, uint256 newFee);

    error InvalidPerformanceFee(uint256 fee);

    /**
     * @notice Performance fee that has accrued since last fee harvest.
     * @return Accrued performance fee in underlying `asset` token.
     * @dev Performance fee is based on a high water mark value. If vault share value has increased above the
     *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
     */
    function accruedPerformanceFee() public view returns (uint256) {
        uint256 highWaterMark_ = highWaterMark;
        uint256 shareValue = convertToAssets(1e18);
        uint256 performanceFee_ = performanceFee;

        return performanceFee_ > 0 && shareValue > highWaterMark_
            ? performanceFee_.mulDiv((shareValue - highWaterMark_) * totalSupply(), 1e36, Math.Rounding.Down)
            : 0;
    }

    /// @notice Minimal function to call `takeFees` modifier.
    function takeManagementAndPerformanceFees()
        external
        nonReentrant
        takeFees
    {}

    /**
     * @notice Set a new performance fee for this adapter. Caller must be owner.
     * @param newFee performance fee in 1e18.
     * @dev Fees can be 0 but never more than 2e17 (1e18 = 100%, 1e14 = 1 BPS)
     */
    function setPerformanceFee(uint256 newFee) public onlyOwner {
        // Dont take more than 20% performanceFee
        if (newFee > 2e17) revert InvalidPerformanceFee(newFee);

        emit PerformanceFeeChanged(performanceFee, newFee);

        performanceFee = newFee;
    }

    // TODO: where to put this? We normally take fees with every harvest.
    // But, what about vaults without a strategy, i.e. that don't harvest.

    /// @notice Collect performance fees and update asset checkpoint.
    modifier takeFees() {
        _;
        uint256 fee = accruedPerformanceFee();
        uint256 shareValue = convertToAssets(1e18);

        if (shareValue > highWaterMark) highWaterMark = shareValue;

        if (fee > 0) _mint(FEE_RECIPIENT, convertToShares(fee));
    }

    VaultFees public fees;

    VaultFees public proposedFees;
    uint256 public proposedFeeTime;

    address public feeRecipient;

    event NewFeesProposed(VaultFees newFees, uint256 timestamp);
    event ChangedFees(VaultFees oldFees, VaultFees newFees);
    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);

    error InvalidVaultFees();
    error InvalidFeeRecipient();
    error NotPassedQuitPeriod(uint256 quitPeriod);

    /**
    * @notice Propose new fees for this vault. Caller must be owner.
    * @param newFees Fees for depositing, withdrawal, management and performance in 1e18.
    * @dev Fees can be 0 but never 1e18 (1e18 = 100%, 1e14 = 1 BPS)
    */
   function proposeFees(VaultFees calldata newFees) external onlyOwner {
       if (
           newFees.deposit >= 1e18 ||
           newFees.withdrawal >= 1e18 ||
           newFees.management >= 1e18 ||
           newFees.performance >= 1e18
       ) revert InvalidVaultFees();

       proposedFees = newFees;
       proposedFeeTime = block.timestamp;

       emit NewFeesProposed(newFees, block.timestamp);
   }

   /// @notice Change fees to the previously proposed fees after the quit period has passed.
   function changeFees() external takeFees {
       if (
           proposedFeeTime == 0 ||
           block.timestamp < proposedFeeTime + quitPeriod
       ) revert NotPassedQuitPeriod(quitPeriod);

       emit ChangedFees(fees, proposedFees);

       fees = proposedFees;
       feesUpdatedAt = block.timestamp;

       delete proposedFees;
       delete proposedFeeTime;
   }

   /**
    * @notice Change `feeRecipient`. Caller must be Owner.
    * @param _feeRecipient The new fee recipient.
    * @dev Accrued fees wont be transferred to the new feeRecipient.
    */
   function setFeeRecipient(address _feeRecipient) external onlyOwner {
       if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

       emit FeeRecipientUpdated(feeRecipient, _feeRecipient);

       feeRecipient = _feeRecipient;
   }

    /*//////////////////////////////////////////////////////////////
                      PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause Deposits and withdraw all funds from the underlying protocol. Caller must be owner.
    function pause() external onlyOwner {
        _deallocate();
        _pause();
    }

    /// @notice Unpause Deposits and deposit all funds into the underlying protocol. Caller must be owner.
    function unpause() external onlyOwner {
        _unpause();
        allocate();
    }

    /*//////////////////////////////////////////////////////////////
                        RAGE QUIT LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public quitPeriod;

    event QuitPeriodSet(uint256 quitPeriod);

    error InvalidQuitPeriod();

    /**
     * @notice Set a quitPeriod for rage quitting after new adapter or fees are proposed. Caller must be Owner.
     * @param _quitPeriod Time to rage quit after proposal.
     */
    function setQuitPeriod(uint256 _quitPeriod) external onlyOwner {
        if (
            block.timestamp < proposedFeeTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);
        if (_quitPeriod < 1 days || _quitPeriod > 7 days)
            revert InvalidQuitPeriod();

        quitPeriod = _quitPeriod;

        emit QuitPeriodSet(quitPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // TODO: need to add this
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    //  EIP-2612 STORAGE
    uint256 internal INITIAL_CHAIN_ID;
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    error PermitDeadlineExpired(uint256 deadline);
    error InvalidSigner(address signer);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
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

            if (recoveredAddress == address(0) || recoveredAddress != owner) {
                revert InvalidSigner(recoveredAddress);
            }

            _approve(recoveredAddress, spender, value);
        }
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

}
