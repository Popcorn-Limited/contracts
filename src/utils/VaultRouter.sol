// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveGauge} from "src/interfaces/external/curve/ICurveGauge.sol";

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
        uint256 preBal = IERC4626(vault).balanceOf(address(this));

        IERC20(gauge).safeTransferFrom(msg.sender, address(this), burnAmount);

        ICurveGauge(gauge).withdraw(burnAmount);

        uint256 postBal = IERC4626(vault).balanceOf(address(this));

        uint256 assets = IERC4626(vault).redeem(
            postBal - preBal,
            receiver,
            address(this)
        );

        if (assets < minOut) revert SlippageTooHigh();
    }

    /*//////////////////////////////////////////////////////////////
                    ASYNCHRONOUS INTERACTION LOGIC
    //////////////////////////////////////////////////////////////*/

    event WithdrawalRequested(
        address indexed vault,
        address indexed asset,
        address indexed receiver,
        address caller,
        uint256 amount
    );
    event WithdrawalFullfilled(
        address indexed vault,
        address indexed asset,
        address indexed receiver,
        uint256 amount
    );
    event WithdrawalClaimed(
        address indexed asset,
        address indexed receiver,
        uint256 amount
    );
    event WithdrawalCancelled(
        address indexed vault,
        address indexed receiver,
        uint256 amount
    );

    error ArrayMismatch();
    //      Vault              Receiver   Amount
    mapping(address => mapping(address => uint256)) public requestShares;
    //      Asset              Receiver   Amount
    mapping(address => mapping(address => uint256)) public claimableAssets;

    function unstakeAndRequestWithdrawal(
        address gauge,
        address vault,
        address receiver,
        uint256 shares
    ) external {
        IERC20(gauge).safeTransferFrom(msg.sender, address(this), shares);

        ICurveGauge(gauge).withdraw(shares);

        _requestWithdrawal(vault, receiver, shares);
    }

    function requestWithdrawal(
        address vault,
        address receiver,
        uint256 shares
    ) external {
        IERC20(vault).safeTransferFrom(msg.sender, address(this), shares);
        _requestWithdrawal(vault, receiver, shares);
    }

    function _requestWithdrawal(
        address vault,
        address receiver,
        uint256 shares
    ) internal {
        requestShares[vault][receiver] += shares;

        emit WithdrawalRequested(
            vault,
            IERC4626(vault).asset(),
            receiver,
            msg.sender,
            shares
        );
    }

    function claimWithdrawal(address asset, address receiver) external {
        uint256 amount = claimableAssets[asset][receiver];
        claimableAssets[asset][receiver] = 0;

        IERC20(asset).safeTransfer(receiver, amount);

        emit WithdrawalClaimed(asset, receiver, amount);
    }

    function fullfillWithdrawal(
        address vault,
        address receiver,
        uint256 shares
    ) external {
        IERC20 asset = IERC20(IERC4626(vault).asset());

        _fullfillWithdrawal(vault, receiver, asset, shares);
    }

    function fullfillWithdrawals(
        address vault,
        address[] memory receivers,
        uint256[] memory shares
    ) external {
        uint256 len = receivers.length;
        if (len != shares.length) revert ArrayMismatch();

        IERC20 asset = IERC20(IERC4626(vault).asset());

        for (uint256 i; i < len; i++) {
            _fullfillWithdrawal(vault, receivers[i], asset, shares[i]);
        }
    }

    function _fullfillWithdrawal(
        address vault,
        address receiver,
        IERC20 asset,
        uint256 shares
    ) internal {
        requestShares[vault][receiver] -= shares;

        uint256 assetAmount = IERC4626(vault).redeem(
            shares,
            address(this),
            address(this)
        );

        claimableAssets[address(asset)][receiver] += assetAmount;

        emit WithdrawalFullfilled(vault, address(asset), receiver, shares);
    }

    function cancelRequest(address vault, uint256 shares) external {
        requestShares[vault][msg.sender] -= shares;

        IERC20(vault).safeTransfer(msg.sender, shares);

        emit WithdrawalCancelled(vault, msg.sender, shares);
    }
}
