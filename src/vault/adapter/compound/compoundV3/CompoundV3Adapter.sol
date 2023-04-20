// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter } from "../../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../../abstracts/WithRewards.sol";
import { ICToken, ICometRewarder, IGovernor, IAdmin, ICometConfigurator } from "./ICompoundV3.sol";

/**
 * @title   CompoundV3 Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for CompoundV3 Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/beefyfinance/beefy-contracts/blob/master/contracts/BIFI/vaults/BeefyVaultV6.sol.
 * Allows wrapping CompoundV3 Vaults with or without an active Booster.
 * Allows for additional strategies to use rewardsToken in case of an active Booster.
 */
contract CompoundV3Adapter is AdapterBase, WithRewards {
  using SafeERC20 for IERC20;
  using Math for uint256;

  string internal _name;
  string internal _symbol;

  /// @notice The Compound cToken contract
  ICToken public cToken;

  /// @notice The Compound Comet rewarder contract.
  ICometRewarder public cometRewarder;

  /// @notice The Compound Comet configurator contract.
  ICometConfigurator public cometConfigurator;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  error InvalidAsset(address asset);

  /**
   * @notice Initialize a new CompoundV3 Adapter.
   * @param adapterInitData Encoded data for the base adapter initialization.
   * @param registry The `CometConfigurator`
   * @param compoundV3InitData Encoded data for the beefy adapter initialization.
   * @dev `_cToken` - The underlying asset supplied to and wrapped by Compound.
   * @dev `_cometRewarder` - The rewards contract
   * @dev This function is called by the factory contract when deploying a new vault.
   */
  function initialize(bytes memory adapterInitData, address registry, bytes memory compoundV3InitData) external initializer {
    __AdapterBase_init(adapterInitData);

    _name = string.concat("VaultCraft CompoundV3 ", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("vcCv3-", IERC20Metadata(asset()).symbol());

    (address _cToken, address _cometRewarder) = abi.decode(
      compoundV3InitData,
      (address, address)
    );

    cToken = ICToken(_cToken);
    cometRewarder = ICometRewarder(_cometRewarder);
    cometConfigurator = ICometConfigurator(registry);

    address configuratorBaseToken = cometConfigurator.getConfiguration(address(cToken)).baseToken;
    if (asset() != configuratorBaseToken) revert InvalidAsset(configuratorBaseToken);

    IERC20(asset()).approve(address(cToken), type(uint256).max);
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
    return cToken.balanceOf(address(this));
  }

  /// @notice The token rewarded if compound liquidity mining is active
  function rewardTokens() external view override returns (address[] memory _rewardTokens) {
    IGovernor governor = IGovernor(cToken.governor());
    IAdmin admin = IAdmin(governor.admin());
    address comp = admin.comp();

    _rewardTokens = new address[](1);
    _rewardTokens[0] = comp;
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  error SupplyPaused();

  /// @notice Deposit into compound cToken contract
  function _protocolDeposit(uint256 amount, uint256) internal virtual override {
    if (cToken.isSupplyPaused() == true) revert SupplyPaused();
    cToken.supply(asset(), amount);
  }

  error WithdrawPaused();

  /// @notice Withdraw from compound cToken contract
  function _protocolWithdraw(uint256 amount, uint256 shares) internal virtual override {
    if (cToken.isWithdrawPaused() == true) revert WithdrawPaused();
    cToken.withdraw(asset(), amount);
  }

  /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

  /// @notice Claim additional rewards given that it's active.
  function claim() public override onlyStrategy returns (bool success) {
    try cometRewarder.claim(address(cToken), address(this), true) {
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
