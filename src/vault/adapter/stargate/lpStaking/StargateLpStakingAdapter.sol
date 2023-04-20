// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter } from "../../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../../abstracts/WithRewards.sol";
import { ISToken, IStargateStaking, IStargateRouter } from "../IStargate.sol";

/**
 * @title   Stargate Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Stargate Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol.
 * Allows wrapping Stargate aTokens with or without an active Liquidity Mining.
 * Allows for additional strategies to use rewardsToken in case of an active Liquidity Mining.
 */

contract StargateLpStakingAdapter is AdapterBase, WithRewards {
  using SafeERC20 for IERC20;
  using Math for uint256;

  string internal _name;
  string internal _symbol;

  uint256 public stakingPid;

  address internal _rewardToken;

  /// @notice The Stargate LpStaking contract
  IStargateStaking public stargateStaking;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

  // TODO add fallback for eth

  error StakingIdOutOfBounds();
  error DifferentAssets();

  /**
   * @notice Initialize a new Stargate Adapter.
   * @param adapterInitData Encoded data for the base adapter initialization.
   * @param registry The Stargate staking contract
   * @param stargateInitData Encoded data for the base adapter initialization.
   * @dev This function is called by the factory contract when deploying a new vault.
   */

  function initialize(
    bytes memory adapterInitData,
    address registry,
    bytes memory stargateInitData
  ) public initializer {
    __AdapterBase_init(adapterInitData);

    uint256 _stakingPid = abi.decode(stargateInitData, (uint256));

    stargateStaking = IStargateStaking(registry);
    if (_stakingPid >= stargateStaking.poolLength()) revert StakingIdOutOfBounds();

    (address sToken, , , ) = stargateStaking.poolInfo(_stakingPid);
    if (sToken != asset()) revert DifferentAssets();

    stakingPid = _stakingPid;
    _rewardToken = stargateStaking.stargate();

    IERC20(asset()).approve(address(stargateStaking), type(uint256).max);

    _name = string.concat("VaultCraft Stargate LpStaking ", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("vcStgLpS-", IERC20Metadata(asset()).symbol());
  }

  function name() public view override(IERC20Metadata, ERC20) returns (string memory) {
    return _name;
  }

  function symbol() public view override(IERC20Metadata, ERC20) returns (string memory) {
    return _symbol;
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
  //////////////////////////////////////////////////////////////*/

  function _totalAssets() internal view override returns (uint256) {
    (uint256 stake, ) = stargateStaking.userInfo(stakingPid, address(this));
    return stake;
  }

  /// @notice The token rewarded if the stargate liquidity mining is active
  function rewardTokens() external view override returns (address[] memory _rewardTokens) {
    _rewardTokens = new address[](1);
    _rewardTokens[0] = _rewardToken;
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Deposit into stargate pool
  function _protocolDeposit(uint256 assets, uint256) internal override {
    stargateStaking.deposit(stakingPid, assets);
  }

  /// @notice Withdraw from stargate pool
  function _protocolWithdraw(uint256 assets, uint256) internal override {
    stargateStaking.withdraw(stakingPid, assets);
  }

  /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  function claim() public override onlyStrategy returns (bool success) {
    try stargateStaking.deposit(stakingPid, 0) {
      success = true;
    } catch {}
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public pure override(WithRewards, AdapterBase) returns (bool) {
    return interfaceId == type(IWithRewards).interfaceId || interfaceId == type(IAdapter).interfaceId;
  }
}
