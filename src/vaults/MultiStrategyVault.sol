// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";
import {VaultFees, IERC4626, IERC20} from "../interfaces/vault/IVault.sol";

struct Allocation {
    uint256 index;
    uint256 amount;
}

/**
 * @title   MultiStrategyVault
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * A simple ERC4626-Implementation of a MultiStrategyVault.
 * The vault delegates any actual protocol interaction to a selection of strategies.
 * It allows for multiple type of fees which are taken by issuing new vault shares.
 * Strategies and fees can be changed by the owner after a ragequit time.
 */
contract MultiStrategyVault is
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnedUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint8 internal _decimals;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error InvalidAsset();
    error InvalidAdapter();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     * @param strategies_ strategies to be used to earn interest for this vault.
     * @param depositLimit_ Maximum amount of assets which can be deposited.
     * @param owner Owner of the contract. Controls management functions.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     */
    function initialize(
        IERC20 asset_,
        IERC4626[] calldata strategies_,
        uint256 depositLimit_,
        address owner
    ) external initializer {
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Owned_init(owner);

        if (address(asset_) == address(0)) revert InvalidAsset();

        uint256 len = strategies_.length;
        for (uint256 i; i < len; i++) {
            if (strategies_[i].asset() != address(asset_))
                revert VaultAssetMismatchNewAdapterAsset();
            strategies.push(strategies_[i]);
            asset_.approve(address(strategies_[i]), type(uint256).max);
        }

        quitPeriod = 3 days;
        depositLimit = depositLimit_;

        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(address(asset_)).name(),
            " Vault"
        );
        _symbol = string.concat(
            "vc-",
            IERC20Metadata(address(asset_)).symbol()
        );

        contractName = keccak256(
            abi.encodePacked("VaultCraft ", name(), block.timestamp, "Vault")
        );

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        emit VaultInitialized(contractName, address(asset_));
    }

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error InvalidReceiver();
    error MaxError(uint256 amount);

    function deposit(uint256 assets) public returns (uint256) {
        return deposit(assets, msg.sender);
    }

    /**
     * @notice Deposit exactly `assets` amount of tokens, issuing vault shares to `receiver`.
     * @param assets Quantity of tokens to deposit.
     * @param receiver Receiver of issued vault shares.
     * @return shares Quantity of vault shares issued to `receiver`.
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant whenNotPaused returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets > maxDeposit(receiver)) revert MaxError(assets);

        shares = previewDeposit(assets);
        if (shares == 0 || assets == 0) revert ZeroAmount();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        // deposit into default index strategy or leave funds idle
        if (defaultDepositIndex != type(uint256).max) {
            strategies[defaultDepositIndex].deposit(assets, address(this));
        }

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
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
        if (receiver == address(0)) revert InvalidReceiver();
        if (shares > maxMint(receiver)) revert MaxError(assets);

        assets = previewMint(shares);
        if (shares == 0 || assets == 0) revert ZeroAmount();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        // deposit into default index strategy or leave funds idle
        if (defaultDepositIndex != type(uint256).max) {
            strategies[defaultDepositIndex].deposit(assets, address(this));
        }

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets) public returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    /**
     * @notice Burn shares from `owner` in exchange for `assets` amount of underlying token.
     * @param assets Quantity of underlying `asset` token to withdraw.
     * @param receiver Receiver of underlying token.
     * @param owner Owner of burned vault shares.
     * @return shares Quantity of vault shares burned in exchange for `assets`.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (assets > maxWithdraw(owner)) revert MaxError(assets);

        shares = previewWithdraw(assets);

        if (shares == 0 || assets == 0) revert ZeroAmount();

        if (msg.sender != owner)
            _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

        _burn(owner, shares);

        _withdrawStrategyFunds(assets, receiver);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /**
     * @notice Burn exactly `shares` vault shares from `owner` and send underlying `asset` tokens to `receiver`.
     * @param shares Quantity of vault shares to exchange for underlying tokens.
     * @param receiver Receiver of underlying tokens.
     * @param owner Owner of burned vault shares.
     * @return assets Quantity of `asset` sent to `receiver`.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        if (receiver == address(0)) revert InvalidReceiver();
        if (shares > maxRedeem(owner)) revert MaxError(shares);

        assets = previewRedeem(shares);

        if (shares == 0 || assets == 0) revert ZeroAmount();

        if (msg.sender != owner)
            _approve(owner, msg.sender, allowance(owner, msg.sender) - shares);

        _burn(owner, shares);

        _withdrawStrategyFunds(assets, receiver);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _withdrawStrategyFunds(uint256 amount, address receiver) internal {
        // caching
        IERC20 asset_ = IERC20(asset());
        uint256[] memory withdrawalQueue_ = withdrawalQueue;

        // Get the Vault's floating balance.
        uint256 float = asset_.balanceOf(address(this));

        if (amount < float) {
            asset_.safeTransfer(receiver, amount);
        } else {
            // If the amount is greater than the float, withdraw from strategies.
            if (float > 0) {
                asset_.safeTransfer(receiver, float);
            }

            // Iterate the withdrawal queue and get indexes
            // Will revert due to underflow if we empty the stack before pulling the desired amount.
            uint256 len = withdrawalQueue_.length;
            for (uint256 i = 0; i < len; i++) {
                uint256 missing = amount - float;

                IERC4626 strategy = strategies[withdrawalQueue_[i]];

                uint256 withdrawableAssets = strategy.previewRedeem(
                    strategy.balanceOf(address(this))
                );

                if (withdrawableAssets >= missing) {
                    strategy.withdraw(missing, receiver, address(this));
                    break;
                } else if (withdrawableAssets > 0) {
                    strategy.withdraw(
                        withdrawableAssets,
                        receiver,
                        address(this)
                    );
                    float += withdrawableAssets;
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev TODO - should we only track deposits / withdrawals and update balances on harvest operations to reduce gas costs?
    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        uint256 assets = IERC20(asset()).balanceOf(address(this));

        for (uint8 i; i < strategies.length; i++) {
            assets += strategies[i].convertToAssets(
                strategies[i].balanceOf(address(this))
            );
        }
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address. Delegates to adapter.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return
            (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return
            (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /*//////////////////////////////////////////////////////////////
                          STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    IERC4626[] public strategies;
    IERC4626[] public proposedStrategies;
    uint256 public proposedStrategyTime;
    uint256 public defaultDepositIndex; // index of the strategy to deposit funds by default - if uint.max, leave funds idle
    uint256[] public withdrawalQueue; // indexes of the strategy order in the withdrawal queue

    event NewStrategiesProposed();
    event ChangedStrategies();

    error VaultAssetMismatchNewAdapterAsset();
    error InvalidIndex();
    error InvalidWithdrawalQueue();

    function getStrategies() external view returns (IERC4626[] memory) {
        return strategies;
    }

    function getProposedStrategies() external view returns (IERC4626[] memory) {
        return proposedStrategies;
    }

    function setDefaultDepositIndex(uint256 index) external onlyOwner {
        if (index > strategies.length - 1 && index != type(uint256).max)
            revert InvalidIndex();

        defaultDepositIndex = index;
    }

    function setWithdrawalQueue(uint256[] memory indexes) external onlyOwner {
        if (indexes.length != strategies.length)
            revert InvalidWithdrawalQueue();

        withdrawalQueue = new uint256[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            uint256 index = indexes[i];

            if (index > strategies.length - 1 && index != type(uint256).max)
                revert InvalidIndex();

            withdrawalQueue[i] = index;
        }
    }

    /**
     * @notice Propose a new adapter for this vault. Caller must be Owner.
     * @param strategies_ A new ERC4626 that should be used as a yield adapter for this asset.
     */
    function proposeStrategies(
        IERC4626[] calldata strategies_
    ) external onlyOwner {
        address asset_ = asset();
        uint256 len = strategies_.length;
        for (uint256 i; i < len; i++) {
            if (strategies_[i].asset() != asset_)
                revert VaultAssetMismatchNewAdapterAsset();
            proposedStrategies.push(strategies_[i]);
        }

        proposedStrategyTime = block.timestamp;
        emit NewStrategiesProposed();
    }

    /**
     * @notice Set a new Adapter for this Vault after the quit period has passed.
     * @dev This migration function will remove all assets from the old Vault and move them into the new vault
     * @dev Additionally it will zero old allowances and set new ones
     * @dev Last we update HWM and assetsCheckpoint for fees to make sure they adjust to the new adapter
     */
    function changeStrategies() external takeFees {
        if (
            proposedStrategyTime == 0 ||
            block.timestamp < proposedStrategyTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);

        address asset_ = asset();
        uint256 len = strategies.length;
        for (uint256 i; i < len; i++) {
            strategies[i].redeem(
                strategies[i].balanceOf(address(this)),
                address(this),
                address(this)
            );
            IERC20(asset_).approve(address(strategies[i]), 0);
        }

        delete strategies;

        len = proposedStrategies.length;
        for (uint256 i; i < len; i++) {
            strategies.push(proposedStrategies[i]);

            IERC20(asset_).approve(
                address(proposedStrategies[i]),
                type(uint256).max
            );
        }

        delete proposedStrategyTime;
        delete proposedStrategies;

        emit ChangedStrategies();
    }

    function pushFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            strategies[allocations[i].index].deposit(
                allocations[i].amount,
                address(this)
            );
        }
    }

    function pullFunds(Allocation[] calldata allocations) external onlyOwner {
        uint256 len = allocations.length;
        for (uint256 i; i < len; i++) {
            if (allocations[i].amount > 0)
                strategies[allocations[i].index].withdraw(
                    allocations[i].amount,
                    address(this),
                    address(this)
                );
        }
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
            block.timestamp < proposedStrategyTime + quitPeriod ||
            block.timestamp < proposedFeeTime + quitPeriod
        ) revert NotPassedQuitPeriod(quitPeriod);
        if (_quitPeriod < 1 days || _quitPeriod > 7 days)
            revert InvalidQuitPeriod();

        quitPeriod = _quitPeriod;

        emit QuitPeriodSet(quitPeriod);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public depositLimit;

    event DepositLimitSet(uint256 depositLimit);

    /**
     * @notice Sets a limit for deposits in assets. Caller must be Owner.
     * @param _depositLimit Maximum amount of assets that can be deposited.
     */
    function setDepositLimit(uint256 _depositLimit) external onlyOwner {
        depositLimit = _depositLimit;

        emit DepositLimitSet(_depositLimit);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause deposits. Caller must be Owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause deposits. Caller must be Owner.
    function unpause() external onlyOwner {
        _unpause();
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
