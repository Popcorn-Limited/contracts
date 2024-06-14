// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveGauge} from "../interfaces/external/curve/ICurveGauge.sol";

/**
 * @title   VaultRouter
 * @author  RedVeil
 * @notice
 *
 */
contract VaultRouter {
    using SafeERC20 for IERC20;

    error SlippageTooHigh();

    constructor() {}

    function depositAndStake(IERC4626 vault, ICurveGauge gauge, uint256 assetAmount, uint256 minOut, address receiver)
        external
    {
        IERC20 asset = IERC20(vault.asset());
        asset.safeTransferFrom(msg.sender, address(this), assetAmount);
        asset.approve(address(vault), assetAmount);

        uint256 shares = vault.deposit(assetAmount, address(this));

        if (shares < minOut) revert SlippageTooHigh();

        vault.approve(address(gauge), shares);
        gauge.deposit(shares, receiver);
    }

    function unstakeAndWithdraw(IERC4626 vault, ICurveGauge gauge, uint256 burnAmount, uint256 minOut, address receiver)
        external
    {
        IERC20(address(gauge)).safeTransferFrom(msg.sender, address(this), burnAmount);

        gauge.withdraw(burnAmount);

        uint256 assets = vault.redeem(burnAmount, receiver, address(this));

        if (assets < minOut) revert SlippageTooHigh();
    }
}
