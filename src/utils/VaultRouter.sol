// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveGauge} from "../interfaces/external/curve/ICurveGauge.sol";

struct WithdrawalRequest {
    address vault;
    uint256 burnAmount;
    uint256 minOut;
    address receiver;
}

/**
 * @title   VaultRouter
 * @author  RedVeil
 * @notice
 */
contract VaultRouter {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public burnPerVault;
    WithdrawalRequest[] public withdrawalQueue;

    error SlippageTooHigh();

    constructor() {}

    function depositAndStake(
        address vault,
        address gauge,
        uint256 assetAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20 asset = IERC20(IERC4626(vault).asset());
        asset.safeTransferFrom(msg.sender, address(this), assetAmount);
        asset.approve(address(vault), assetAmount);

        uint256 shares = IERC4626(vault).deposit(assetAmount, address(this));

        if (shares < minOut) revert SlippageTooHigh();

        IERC4626(vault).approve(gauge, shares);
        ICurveGauge(gauge).deposit(shares, receiver);
    }

    function unstakeAndWithdraw(
        address vault,
        address gauge,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), burnAmount);

        ICurveGauge(gauge).withdraw(burnAmount);

        uint256 assets = IERC4626(vault).redeem(
            burnAmount,
            receiver,
            address(this)
        );

        if (assets < minOut) revert SlippageTooHigh();
    }

    function unstakeAndRequestWithdrawal(
        address vault,
        address gauge,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), burnAmount);

        ICurveGauge(gauge).withdraw(burnAmount);

        _requestWithdrawal(vault, burnAmount, minOut, receiver);
    }

    function requestWithdrawal(
        address vault,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) external {
        IERC20(vault).safeTransferFrom(msg.sender, address(this), burnAmount);
        _requestWithdrawal(vault, burnAmount, minOut, receiver);
    }

    function _requestWithdrawal(
        address vault,
        uint256 burnAmount,
        uint256 minOut,
        address receiver
    ) internal {
        withdrawalQueue.push(
            WithdrawalRequest({
                vault: vault,
                burnAmount: burnAmount,
                minOut: minOut,
                receiver: receiver
            })
        );
    }

    function fullfillWithdrawal() external {}
}
