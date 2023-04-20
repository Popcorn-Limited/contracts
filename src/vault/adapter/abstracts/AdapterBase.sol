// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { ERC4626Upgradeable, IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata, ERC20Upgradeable as ERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { MathUpgradeable as Math } from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import { IStrategy } from "../../../interfaces/vault/IStrategy.sol";
import { IAdapter, IERC4626 } from "../../../interfaces/vault/IAdapter.sol";
import { EIP165 } from "../../../utils/EIP165.sol";
import { OnlyStrategy } from "./OnlyStrategy.sol";
import { OwnedUpgradeable } from "../../../utils/OwnedUpgradeable.sol";

/**
 * @title   AdapterBase
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
abstract contract AdapterBase is
  ERC4626Upgradeable,
  PausableUpgradeable,
  OwnedUpgradeable,
  ReentrancyGuardUpgradeable,
  EIP165,
  OnlyStrategy
{
  using SafeERC20 for IERC20;
  using Math for uint256;

  uint8 internal _decimals;
  uint8 public constant decimalOffset = 9;

  error StrategySetupFailed();

  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initialize a new Adapter.
   * @param popERC4626InitData Encoded data for the base adapter initialization.
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
  function __AdapterBase_init(bytes memory popERC4626InitData) internal onlyInitializing {
    (
      address asset,
      address _owner,
      address _strategy,
      uint256 _harvestCooldown,
      bytes4[8] memory _requiredSigs,
      bytes memory _strategyConfig
    ) = abi.decode(popERC4626InitData, (address, address, address, uint256, bytes4[8], bytes));
    __Owned_init(_owner);
    __Pausable_init();
    __ERC4626_init(IERC20Metadata(asset));

    INITIAL_CHAIN_ID = block.chainid;
    INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

    _decimals = IERC20Metadata(asset).decimals() + decimalOffset; // Asset decimals + decimal offset to combat inflation attacks

    strategy = IStrategy(_strategy);
    strategyConfig = _strategyConfig;
    harvestCooldown = _harvestCooldown;

    if (_strategy != address(0)) _verifyAndSetupStrategy(_requiredSigs);

    highWaterMark = 1e9;
    lastHarvest = block.timestamp;
  }

  function decimals() public view override(IERC20Metadata, ERC20) returns (uint8) {
    return _decimals;
  }

  /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

  error MaxError(uint256 amount);
  error ZeroAmount();

  /**
   * @notice Deposit `assets` into the underlying protocol and mints vault shares to `receiver`.
   * @dev Executes harvest if `harvestCooldown` is passed since last invocation.
   */
  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  ) internal virtual override nonReentrant {
    IERC20(asset()).safeTransferFrom(caller, address(this), assets);

    _protocolDeposit(assets, shares);
    _mint(receiver, shares);

    harvest();

    emit Deposit(caller, receiver, assets, shares);
  }

  /**
   * @notice Withdraws `assets` from the underlying protocol and burns vault shares from `owner`.
   * @dev Executes harvest if `harvestCooldown` is passed since last invocation.
   */
  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) internal virtual override {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }

    if (!paused()) {
      _protocolWithdraw(assets, shares);
    }

    _burn(owner, shares);

    IERC20(asset()).safeTransfer(receiver, assets);

    harvest();

    emit Withdraw(caller, receiver, owner, assets, shares);
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

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
  function _totalAssets() internal view virtual returns (uint256) {}

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

  function _convertToShares(
    uint256 assets,
    Math.Rounding rounding
  ) internal view virtual override returns (uint256 shares) {
    return assets.mulDiv(totalSupply() + 10 ** decimalOffset, totalAssets() + 1, rounding);
  }

  function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
    return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** decimalOffset, rounding);
  }

  /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

  /**
   * @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
   * @dev Return 0 if paused since no further deposits are allowed.
   * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
   */
  function maxDeposit(address) public view virtual override returns (uint256) {
    return paused() ? 0 : type(uint256).max;
  }

  /**
   * @return Maximum amount of vault shares that may be minted to given address. Delegates to adapter.
   * @dev Return 0 if paused since no further deposits are allowed.
   * @dev Override this function if the underlying protocol has a unique deposit logic and/or deposit fees.
   */
  function maxMint(address) public view virtual override returns (uint256) {
    return paused() ? 0 : type(uint256).max;
  }

  /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  IStrategy public strategy;
  bytes public strategyConfig;
  uint256 public lastHarvest;

  event Harvested();

  /**
   * @notice Execute Strategy and take fees.
   * @dev Delegatecall to strategy's harvest() function. All necessary data is passed via `strategyConfig`.
   * @dev Delegatecall is used to in case any logic requires the adapters address as a msg.sender. (e.g. Synthetix staking)
   */
  function harvest() public takeFees {
    if (address(strategy) != address(0) && ((lastHarvest + harvestCooldown) < block.timestamp)) {
      // solhint-disable
      (bool success, ) = address(strategy).delegatecall(abi.encodeWithSignature("harvest()"));
      if (!success) revert();
      lastHarvest = block.timestamp;
    }

    emit Harvested();
  }

  /**
   * @notice Allows the strategy to deposit assets into the underlying protocol without minting new adapter shares.
   * @dev This can be used e.g. for a compounding strategy to increase the value of each adapter share.
   */
  function strategyDeposit(uint256 amount, uint256 shares) public onlyStrategy {
    _protocolDeposit(amount, shares);
  }

  /**
   * @notice Allows the strategy to withdraw assets from the underlying protocol without burning adapter shares.
   * @dev This can be used e.g. for a leverage strategy to reduce leverage without the need for the strategy to hold any adapter shares.
   */
  function strategyWithdraw(uint256 amount, uint256 shares) public onlyStrategy {
    _protocolWithdraw(amount, shares);
  }

  /**
   * @notice Verifies that the Adapter and Strategy are compatible and sets up the strategy.
   * @dev This checks EIP165 compatibility and potentially other strategy specific checks (matching assets...).
   * @dev It aftwards sets up anything required by the strategy to call `harvest()` like approvals etc.
   */
  function _verifyAndSetupStrategy(bytes4[8] memory requiredSigs) internal {
    strategy.verifyAdapterSelectorCompatibility(requiredSigs);
    strategy.verifyAdapterCompatibility(strategyConfig);
    strategy.setUp(strategyConfig);
  }

  /*//////////////////////////////////////////////////////////////
                      HARVEST COOLDOWN LOGIC
  //////////////////////////////////////////////////////////////*/

  uint256 public harvestCooldown;

  event HarvestCooldownChanged(uint256 oldCooldown, uint256 newCooldown);

  error InvalidHarvestCooldown(uint256 cooldown);

  /**
   * @notice Set a new harvestCooldown for this adapter. Caller must be owner.
   * @param newCooldown Time in seconds that must pass before a harvest can be called again.
   * @dev Cant be longer than 1 day.
   */
  function setHarvestCooldown(uint256 newCooldown) external onlyOwner {
    // Dont wait more than X seconds
    if (newCooldown >= 1 days) revert InvalidHarvestCooldown(newCooldown);

    emit HarvestCooldownChanged(harvestCooldown, newCooldown);

    harvestCooldown = newCooldown;
  }

  /*//////////////////////////////////////////////////////////////
                      FEE LOGIC
  //////////////////////////////////////////////////////////////*/

  uint256 public performanceFee;
  uint256 public highWaterMark;

  // TODO use deterministic fee recipient proxy
  address public constant FEE_RECIPIENT = address(0x74bb390786072ea1329f270CA6C0058b2D1Afe3f);

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

    return
      performanceFee_ > 0 && shareValue > highWaterMark_
        ? performanceFee_.mulDiv((shareValue - highWaterMark_) * totalSupply(), 1e36, Math.Rounding.Down)
        : 0;
  }

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

  /// @notice Collect performance fees and update asset checkpoint.
  modifier takeFees() {
    _;
    uint256 fee = accruedPerformanceFee();
    uint256 shareValue = convertToAssets(1e18);

    if (shareValue > highWaterMark) highWaterMark = shareValue;

    if (fee > 0) _mint(FEE_RECIPIENT, convertToShares(fee));
  }

  /*//////////////////////////////////////////////////////////////
                      PAUSING LOGIC
  //////////////////////////////////////////////////////////////*/

  /// @notice Pause Deposits and withdraw all funds from the underlying protocol. Caller must be owner.
  function pause() external onlyOwner {
    _protocolWithdraw(totalAssets(), totalSupply());
    _pause();
  }

  /// @notice Unpause Deposits and deposit all funds into the underlying protocol. Caller must be owner.
  function unpause() external onlyOwner {
    _protocolDeposit(totalAssets(), totalSupply());
    _unpause();
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice deposit into the underlying protocol.
  function _protocolDeposit(uint256 assets, uint256 shares) internal virtual {
    // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
  }

  /// @notice Withdraw from the underlying protocol.
  function _protocolWithdraw(uint256 assets, uint256 shares) internal virtual {
    // OPTIONAL - convertIntoUnderlyingShares(assets,shares)
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(IAdapter).interfaceId;
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
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
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

      if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSigner(recoveredAddress);

      _approve(recoveredAddress, spender, value);
    }
  }

  function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
    return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
  }

  function computeDomainSeparator() internal view virtual returns (bytes32) {
    return
      keccak256(
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
