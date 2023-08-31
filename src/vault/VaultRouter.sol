// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IVaultRegistry, VaultMetadata} from "../interfaces/vault/IVaultRegistry.sol";
import {ICurveGauge} from "../interfaces/external/curve/ICurveGauge.sol";

/**
 * @title   VaultRouter
 * @author  RedVeil
 * @notice
 *
 */
contract VaultRouter {
    using SafeERC20 for IERC20;

    constructor() {}

    function depositAndStake(
        IERC4626 vault,
        ICurveGauge gauge,
        uint256 assetAmount,
        address receiver
    ) external {
        IERC20 asset = IERC20(vault.asset());
        asset.safeTransferFrom(msg.sender, address(this), assetAmount);
        asset.approve(address(vault), assetAmount);

        uint256 shares = vault.deposit(assetAmount, address(this));

        vault.approve(address(gauge), shares);
        gauge.deposit(shares, receiver);
    }

    function unstakeAndWithdraw(
        IERC4626 vault,
        ICurveGauge gauge,
        uint256 burnAmount,
        address receiver
    ) external {
        IERC20(address(gauge)).safeTransferFrom(msg.sender, address(this), burnAmount);

        gauge.withdraw(burnAmount);

        vault.redeem(burnAmount, receiver, address(this));
    }
}
