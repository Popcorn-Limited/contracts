// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20, IERC20MetadataUpgradeable as IERC20Metadata } from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import { ERC4626Upgradeable, ERC20Upgradeable as ERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { MathUpgradeable as Math } from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";

contract MockERC4626 is ERC4626Upgradeable {
  using SafeERC20 for IERC20;
  using Math for uint256;

  uint256 public beforeWithdrawHookCalledCounter = 0;
  uint256 public afterDepositHookCalledCounter = 0;

  uint8 internal _decimals;
  uint8 public constant decimalOffset = 9;

  /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

  function initialize(
    IERC20 _asset,
    string memory _name,
    string memory _symbol
  ) external initializer {
    __ERC4626_init(IERC20Metadata(address(_asset)));
    _decimals = IERC20Metadata(address(_asset)).decimals() + decimalOffset;
  }

  /*//////////////////////////////////////////////////////////////
                            GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
    return assets.mulDiv(totalSupply() + 10**decimalOffset, totalAssets() + 1, rounding);
  }

  function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
    return shares.mulDiv(totalAssets() + 1, totalSupply() + 10**decimalOffset, rounding);
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

  function _deposit(
    address caller,
    address receiver,
    uint256 assets,
    uint256 shares
  ) internal override {
    IERC20(asset()).safeTransferFrom(caller, address(this), assets);
    _mint(receiver, shares);

    afterDepositHookCalledCounter++;

    emit Deposit(caller, receiver, assets, shares);
  }

  function _withdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    uint256 shares
  ) internal override {
    if (caller != owner) {
      _spendAllowance(owner, caller, shares);
    }

    beforeWithdrawHookCalledCounter++;

    _burn(owner, shares);
    IERC20(asset()).safeTransfer(receiver, assets);

    emit Withdraw(caller, receiver, owner, assets, shares);
  }
}
