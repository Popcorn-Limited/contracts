// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter } from "../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../abstracts/WithRewards.sol";
import { IAuraBooster, IAuraRewards, IAuraStaking } from "./IAura.sol";

/**
 * @title  Aura Adapter
 * @author amatureApe
 * @notice ERC4626 wrapper for Aura Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/Aura.sol.
 * Allows wrapping Aura Vaults.
 */
contract AuraAdapter is AdapterBase, WithRewards {
  using SafeERC20 for IERC20;
  using Math for uint256;

  string internal _name;
  string internal _symbol;

  /// @notice The Aura booster contract
  IAuraBooster public auraBooster;

  /// @notice The reward contract for Aura gauge
  IAuraRewards public auraRewards;

  /// @notice The pool ID
  uint256 public pid;

  address public crv;
  address public cvx;
  address[] internal _rewardToken;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  error InvalidAsset();

  /**
   * @notice Initialize a new Aura Adapter.
   * @param adapterInitData Encoded data for the base adapter initialization.
   * @param registry `_auraBooster` - The main Aura contract
   * @param auraInitData aura specific init data
   * @dev `_pid` - The poolId for lpToken.
   * @dev This function is called by the factory contract when deploying a new vault.
   */

  function initialize(bytes memory adapterInitData, address registry, bytes memory auraInitData) external initializer {
    __AdapterBase_init(adapterInitData);

    uint256 _pid = abi.decode(auraInitData, (uint256));

    auraBooster = IAuraBooster(registry);
    pid = _pid;

    IAuraStaking auraStaking = IAuraStaking(auraBooster.stakerRewards());
    crv = auraStaking.crv();
    _rewardToken.push(crv);
    cvx = auraStaking.cvx();
    _rewardToken.push(cvx);

    (address balancerLpToken, , , address _auraRewards, , ) = auraBooster.poolInfo(pid);

    auraRewards = IAuraRewards(_auraRewards);

    if (balancerLpToken != asset()) revert InvalidAsset();

    _name = string.concat("VaultCraft Aura ", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("vcAu-", IERC20Metadata(asset()).symbol());

    IERC20(balancerLpToken).approve(address(auraBooster), type(uint256).max);
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

  /// @notice Calculates the total amount of underlying tokens the Vault holds.
  /// @return The total amount of underlying tokens the Vault holds.

  function _totalAssets() internal view override returns (uint256) {
    return auraRewards.balanceOf(address(this));
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _protocolDeposit(uint256 amount, uint256) internal override {
    auraBooster.deposit(pid, amount, true);
  }

  function _protocolWithdraw(uint256 amount, uint256) internal override {
    auraRewards.withdrawAndUnwrap(amount, true);
  }

  /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Claim rewards from the aura
  function claim() public override onlyStrategy returns (bool success) {
    try auraRewards.getReward() {
      success = true;
    } catch {}
  }

  /// @notice The token rewarded
  function rewardTokens() external view override returns (address[] memory) {
    return _rewardToken;
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public pure override(WithRewards, AdapterBase) returns (bool) {
    return interfaceId == type(IWithRewards).interfaceId || interfaceId == type(IAdapter).interfaceId;
  }
}
