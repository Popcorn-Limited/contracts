// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626 } from "../abstracts/AdapterBase.sol";
import { WithRewards, IWithRewards } from "../abstracts/WithRewards.sol";

/**
 * @title   Ousd Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Ousd Vault.
 *
 * An ERC4626 compliant Wrapper for https://github.com/sushiswap/sushiswap/blob/archieve/canary/contracts/MasterChefV2.sol.
 * Allows wrapping Ousd.
 */
contract OusdAdapter is AdapterBase, WithRewards {
  using SafeERC20 for IERC20;
  using Math for uint256;

  string internal _name;
  string internal _symbol;

  /// @notice The wOUSD token contract.
  IERC4626 public wOusd;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  error InvalidAsset();

  /**
   * @notice Initialize a new MasterChef Adapter.
   * @param adapterInitData Encoded data for the base adapter initialization.
   * @dev `_ousd` - The address of the OUSD token.
   * @dev This function is called by the factory contract when deploying a new vault.
   */

  function initialize(bytes memory adapterInitData, address registry, bytes memory ousdInitData) external initializer {
    __AdapterBase_init(adapterInitData);

    address _wousd = abi.decode(ousdInitData, (address));

    wOusd = IERC4626(_wousd);

    _name = string.concat("VaultCraft Ousd ", IERC20Metadata(asset()).name(), " Adapter");
    _symbol = string.concat("vcO-", IERC20Metadata(asset()).symbol());

    IERC20(asset()).approve(address(wOusd), type(uint256).max);
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
    return wOusd.convertToAssets(wOusd.balanceOf(address(this)));
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _protocolDeposit(uint256 amount, uint256) internal override {
    wOusd.deposit(amount, address(this));
  }

  function _protocolWithdraw(uint256 amount, uint256) internal override {
    wOusd.withdraw(amount, address(this), address(this));
  }

  /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

  function supportsInterface(bytes4 interfaceId) public pure override(WithRewards, AdapterBase) returns (bool) {
    return interfaceId == type(IWithRewards).interfaceId || interfaceId == type(IAdapter).interfaceId;
  }
}
