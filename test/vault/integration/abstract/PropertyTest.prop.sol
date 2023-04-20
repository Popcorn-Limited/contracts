// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { EnhancedTest } from "../../../utils/EnhancedTest.sol";
import { IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";

contract PropertyTest is EnhancedTest {
  uint256 internal _delta_;

  address internal _asset_;
  address internal _vault_;

  /*//////////////////////////////////////////////////////////////
                          ASSET VIEWS
    //////////////////////////////////////////////////////////////*/

  // "MUST NOT revert."
  function prop_asset() public view {
    IERC4626(_vault_).asset();
  }

  // "MUST NOT revert."
  function prop_totalAssets() public view {
    IERC4626(_vault_).totalAssets();
  }

  /*//////////////////////////////////////////////////////////////
                          CONVERSION VIEWS
    //////////////////////////////////////////////////////////////*/

  // "MUST NOT show any variations depending on the caller."
  function prop_convertToShares(
    address caller1,
    address caller2,
    uint256 assets
  ) public {
    vm.prank(caller1);
    uint256 res1 = IERC4626(_vault_).convertToShares(assets); // "MAY revert due to integer overflow caused by an unreasonably large input."
    vm.prank(caller2);
    uint256 res2 = IERC4626(_vault_).convertToShares(assets); // "MAY revert due to integer overflow caused by an unreasonably large input."
    assertEq(res1, res2);
  }

  // "MUST NOT show any variations depending on the caller."
  function prop_convertToAssets(
    address caller1,
    address caller2,
    uint256 shares
  ) public {
    vm.prank(caller1);
    uint256 res1 = IERC4626(_vault_).convertToAssets(shares); // "MAY revert due to integer overflow caused by an unreasonably large input."
    vm.prank(caller2);
    uint256 res2 = IERC4626(_vault_).convertToAssets(shares); // "MAY revert due to integer overflow caused by an unreasonably large input."
    assertEq(res1, res2);
  }

  /*//////////////////////////////////////////////////////////////
                          MAX VIEWS
    //////////////////////////////////////////////////////////////*/

  // "MUST NOT revert."
  function prop_maxDeposit(address caller) public view {
    IERC4626(_vault_).maxDeposit(caller);
  }

  // "MUST NOT revert."
  function prop_maxMint(address caller) public view {
    IERC4626(_vault_).maxMint(caller);
  }

  // "MUST NOT revert."
  // NOTE: some implementations failed due to arithmetic overflow
  function prop_maxWithdraw(address caller) public view {
    IERC4626(_vault_).maxWithdraw(caller);
  }

  // "MUST NOT revert."
  function prop_maxRedeem(address caller) public view {
    IERC4626(_vault_).maxRedeem(caller);
  }

  /*//////////////////////////////////////////////////////////////
                          PREVIEW VIEWS
    //////////////////////////////////////////////////////////////*/

  // "MUST return as close to and no more than the exact amount of _vault_
  // shares that would be minted in a deposit call in the same transaction.
  // I.e. deposit should return the same or more shares as previewDeposit if
  // called in the same transaction."
  function prop_previewDeposit(
    address caller,
    address receiver,
    uint256 assets,
    string memory testPreFix
  ) public {
    uint256 sharesPreview = IERC4626(_vault_).previewDeposit(assets); // "MAY revert due to other conditions that would also cause deposit to revert."

    vm.prank(caller);
    uint256 sharesActual = IERC4626(_vault_).deposit(assets, receiver);

    assertGe(sharesActual, sharesPreview, testPreFix);
  }

  // "MUST return as close to and no fewer than the exact amount of assets
  // that would be deposited in a mint call in the same transaction. I.e. mint
  // should return the same or fewer assets as previewMint if called in the
  // same transaction."
  function prop_previewMint(
    address caller,
    address receiver,
    uint256 shares,
    string memory testPreFix
  ) public {
    uint256 assetsPreview = IERC4626(_vault_).previewMint(shares);

    vm.prank(caller);
    uint256 assetsActual = IERC4626(_vault_).mint(shares, receiver);

    assertLe(assetsActual, assetsPreview, testPreFix);
  }

  // "MUST return as close to and no fewer than the exact amount of _vault_
  // shares that would be burned in a withdraw call in the same transaction.
  // I.e. withdraw should return the same or fewer shares as previewWithdraw
  // if called in the same transaction."
  function prop_previewWithdraw(
    address caller,
    address receiver,
    address owner,
    uint256 assets,
    string memory testPreFix
  ) public {
    uint256 preview = IERC4626(_vault_).previewWithdraw(assets);

    vm.prank(caller);
    uint256 actual = IERC4626(_vault_).withdraw(assets, receiver, owner);

    assertLe(actual, preview, testPreFix);
  }

  // "MUST return as close to and no more than the exact amount of assets that
  // would be withdrawn in a redeem call in the same transaction. I.e. redeem
  // should return the same or more assets as previewRedeem if called in the
  // same transaction."
  function prop_previewRedeem(
    address caller,
    address receiver,
    address owner,
    uint256 shares,
    string memory testPreFix
  ) public {
    uint256 preview = IERC4626(_vault_).previewRedeem(shares);
    vm.prank(caller);
    uint256 actual = IERC4626(_vault_).redeem(shares, receiver, owner);
    assertGe(actual, preview, testPreFix);
  }

  /*//////////////////////////////////////////////////////////////
                    DEPOSIT/MINT/WITHDRAW/REDEEM
    //////////////////////////////////////////////////////////////*/

  function prop_deposit(
    address caller,
    address receiver,
    uint256 assets,
    string memory testPreFix
  ) public returns (uint256 paid, uint256 received) {
    uint256 oldCallerAsset = IERC20(_asset_).balanceOf(caller);
    uint256 oldReceiverShare = IERC20(_vault_).balanceOf(receiver);
    uint256 oldAllowance = IERC20(_asset_).allowance(caller, _vault_);

    vm.prank(caller);
    uint256 shares = IERC4626(_vault_).deposit(assets, receiver);

    uint256 newCallerAsset = IERC20(_asset_).balanceOf(caller);
    uint256 newReceiverShare = IERC20(_vault_).balanceOf(receiver);
    uint256 newAllowance = IERC20(_asset_).allowance(caller, _vault_);

    assertApproxEqAbs(newCallerAsset, oldCallerAsset - assets, _delta_, string.concat("asset", testPreFix)); // NOTE: this may fail if the caller is a contract in which the asset is stored
    assertApproxEqAbs(newReceiverShare, oldReceiverShare + shares, _delta_, string.concat("share", testPreFix));
    if (oldAllowance != type(uint256).max)
      assertApproxEqAbs(newAllowance, oldAllowance - assets, _delta_, string.concat("allowance", testPreFix));

    return (assets, shares);
  }

  function prop_mint(
    address caller,
    address receiver,
    uint256 shares,
    string memory testPreFix
  ) public returns (uint256 paid, uint256 received) {
    uint256 oldCallerAsset = IERC20(_asset_).balanceOf(caller);
    uint256 oldReceiverShare = IERC20(_vault_).balanceOf(receiver);
    uint256 oldAllowance = IERC20(_asset_).allowance(caller, _vault_);

    vm.prank(caller);
    uint256 assets = IERC4626(_vault_).mint(shares, receiver);

    uint256 newCallerAsset = IERC20(_asset_).balanceOf(caller);
    uint256 newReceiverShare = IERC20(_vault_).balanceOf(receiver);
    uint256 newAllowance = IERC20(_asset_).allowance(caller, _vault_);

    assertApproxEqAbs(newCallerAsset, oldCallerAsset - assets, _delta_, string.concat("asset", testPreFix)); // NOTE: this may fail if the caller is a contract in which the asset is stored
    assertApproxEqAbs(newReceiverShare, oldReceiverShare + shares, _delta_, string.concat("share", testPreFix));
    if (oldAllowance != type(uint256).max)
      assertApproxEqAbs(newAllowance, oldAllowance - assets, _delta_, string.concat("allowance", testPreFix));

    return (assets, shares);
  }

  // Simplifing it here a little to avoid `Stack to Deep` - Caller = Receiver
  function prop_withdraw(
    address caller,
    address owner,
    uint256 assets,
    string memory testPreFix
  ) public returns (uint256 paid, uint256 received) {
    uint256 oldReceiverAsset = IERC20(_asset_).balanceOf(caller);
    uint256 oldOwnerShare = IERC20(_vault_).balanceOf(owner);
    uint256 oldAllowance = IERC20(_vault_).allowance(owner, caller);

    vm.prank(caller);
    uint256 shares = IERC4626(_vault_).withdraw(assets, caller, owner);

    uint256 newReceiverAsset = IERC20(_asset_).balanceOf(caller);
    uint256 newOwnerShare = IERC20(_vault_).balanceOf(owner);
    uint256 newAllowance = IERC20(_vault_).allowance(owner, caller);

    assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, string.concat("share", testPreFix));
    assertApproxEqAbs(newReceiverAsset, oldReceiverAsset + assets, _delta_, string.concat("asset", testPreFix)); // NOTE: this may fail if the receiver is a contract in which the asset is stored
    if (caller != owner && oldAllowance != type(uint256).max)
      assertApproxEqAbs(newAllowance, oldAllowance - shares, _delta_, string.concat("allowance", testPreFix));

    assertTrue(
      caller == owner || oldAllowance != 0 || (shares == 0 && assets == 0),
      string.concat("access control", testPreFix)
    );

    return (shares, assets);
  }

  // Simplifing it here a little to avoid `Stack to Deep` - Caller = Receiver
  function prop_redeem(
    address caller,
    address owner,
    uint256 shares,
    string memory testPreFix
  ) public returns (uint256 paid, uint256 received) {
    uint256 oldReceiverAsset = IERC20(_asset_).balanceOf(caller);
    uint256 oldOwnerShare = IERC20(_vault_).balanceOf(owner);
    uint256 oldAllowance = IERC20(_vault_).allowance(owner, caller);

    vm.prank(caller);
    uint256 assets = IERC4626(_vault_).redeem(shares, caller, owner);

    uint256 newReceiverAsset = IERC20(_asset_).balanceOf(caller);
    uint256 newOwnerShare = IERC20(_vault_).balanceOf(owner);
    uint256 newAllowance = IERC20(_vault_).allowance(owner, caller);

    assertApproxEqAbs(newOwnerShare, oldOwnerShare - shares, _delta_, string.concat("share", testPreFix));
    assertApproxEqAbs(newReceiverAsset, oldReceiverAsset + assets, _delta_, string.concat("asset", testPreFix)); // NOTE: this may fail if the receiver is a contract in which the asset is stored
    if (caller != owner && oldAllowance != type(uint256).max)
      assertApproxEqAbs(newAllowance, oldAllowance - shares, _delta_, string.concat("allowance", testPreFix));

    assertTrue(
      caller == owner || oldAllowance != 0 || (shares == 0 && assets == 0),
      string.concat("access control", testPreFix)
    );

    return (shares, assets);
  }
}
