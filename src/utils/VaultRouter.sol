// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveGauge} from "src/interfaces/external/curve/ICurveGauge.sol";
import {IAsyncVault} from "src/interfaces/IAsyncVault.sol";

/**
 * @title   VaultRouter
 * @author  RedVeil
 * @notice
 */
contract VaultRouter {
    using SafeERC20 for IERC20;

    constructor() {}

    /*//////////////////////////////////////////////////////////////
                    SYNCHRONOUS INTERACTION LOGIC
    //////////////////////////////////////////////////////////////*/

    error SlippageTooHigh();

    /**
     * @notice Deposit and stake assets in a vault and gauge (Works both for ERC4626 and ERC7540 vaults)
     * @param vault The vault to deposit and stake in
     * @param gauge The gauge to stake in
     * @param assets The amount of assets to deposit and stake
     * @param minOut The minimum amount of shares to receive
     * @param receiver The receiver of the shares
     */
    function depositAndStake(
        address vault,
        address gauge,
        uint256 assets,
        uint256 minOut,
        address receiver
    ) external {
        // Here to reduce user input
        IERC20 asset = IERC20(IERC4626(vault).asset());

        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.approve(address(vault), assets);

        uint256 shares = IERC4626(vault).deposit(assets, address(this));

        if (shares < minOut) revert SlippageTooHigh();

        IERC4626(vault).approve(gauge, shares);
        ICurveGauge(gauge).deposit(shares, receiver);
    }

    /**
     * @notice Unstake and withdraw assets from a gauge and vault (ONLY works both for ERC4626)
     * @param vault The vault to deposit and stake in
     * @param gauge The gauge to stake in
     * @param shares The amount of shares to burn
     * @param minOut The minimum amount of assets to receive
     * @param receiver The receiver of the assets
     */
    function unstakeAndWithdraw(
        address vault,
        address gauge,
        uint256 shares,
        uint256 minOut,
        address receiver
    ) external {
        uint256 preBal = IERC4626(vault).balanceOf(address(this));

        _unstake(gauge, shares);

        uint256 postBal = IERC4626(vault).balanceOf(address(this));

        uint256 assets = IERC4626(vault).redeem(
            postBal - preBal,
            receiver,
            address(this)
        );

        if (assets < minOut) revert SlippageTooHigh();
    }

    /// @notice Internal function to unstake shares from a gauge
    function _unstake(address gauge, uint256 shares) internal {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), shares);
        ICurveGauge(gauge).withdraw(shares);
    }

    /*//////////////////////////////////////////////////////////////
                    ASYNCHRONOUS INTERACTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Unstake and request withdrawal from a vault (ONLY works for ERC7540 vaults)
     * @param vault The vault to request withdrawal from
     * @param gauge The gauge to unstake from
     * @param shares The amount of shares to unstake
     * @param receiver The receiver of the shares
     */
    function unstakeAndRequestWithdrawal(
        address gauge,
        address vault,
        address receiver,
        uint256 shares
    ) external {
        _unstake(gauge, shares);
        _requestWithdrawal(vault, receiver, shares);
    }

    /**
     * @notice Instantly unstake and withdraw your assets from a vault with all the necessary request and fulfill logic (ONLY works for ERC7540 vaults)
     * @param gauge The gauge to unstake from
     * @param vault The vault to request withdrawal from
     * @param receiver The receiver of the shares
     * @param shares The amount of shares to unstake
     * @dev This function will unstake from the gauge, request a withdrawal from the vault, and immediately fulfill the withdrawal before redeeming the shares making the vault effectivly instant and synchronous
     * @dev This router must be enabled as `controller` on the vault by the `receiver`
     */
    function unstakeRequestFulfillWithdraw(
        address gauge,
        address vault,
        address receiver,
        uint256 shares
    ) external {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), shares);

        ICurveGauge(gauge).withdraw(shares);

        _requestFulfillWithdraw(vault, receiver, shares);
    }

    /**
     * @notice Instantly withdraw your assets from a vault with all the necessary request and fulfill logic (ONLY works for ERC7540 vaults)
     * @param vault The vault to request withdrawal from
     * @param receiver The receiver of the shares
     * @param shares The amount of shares to unstake
     * @dev This function will request a withdrawal from the vault, and immediately fulfill the withdrawal before redeeming the shares making the vault effectivly instant and synchronous
     * @dev This router must be enabled as `controller` on the vault by the `receiver`
     */
    function requestFulfillWithdraw(
        address vault,
        address receiver,
        uint256 shares
    ) external {
        _requestFulfillWithdraw(vault, receiver, shares);
    }

    /// @notice Internal function to request and fulfill and execute a withdrawal from a vault
    function _requestFulfillWithdraw(
        address vault,
        address receiver,
        uint256 shares
    ) internal {
        _requestWithdrawal(vault, receiver, shares);

        IAsyncVault(vault).fulfillRedeem(shares, receiver);

        IERC4626(vault).redeem(shares, receiver, receiver);
    }

    /// @notice Internal function to fulfill a withdrawal from a vault
    function _fulfillWithdrawal(
        address vault,
        address receiver,
        uint256 shares
    ) internal {
        IAsyncVault(vault).fulfillRedeem(shares, receiver);
        IERC4626(vault).redeem(shares, receiver, receiver);
    }

    /// @notice Internal function to request a withdrawal from a vault
    function _requestWithdrawal(
        address vault,
        address receiver,
        uint256 shares
    ) internal {
        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);

        // allow vault to pull shares
        IERC20(vault).safeIncreaseAllowance(vault, shares);

        // request redeem - send shares to vault
        IAsyncVault(vault).requestRedeem(shares, receiver, address(this));
    }
}
