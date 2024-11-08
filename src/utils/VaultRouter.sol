// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveGauge} from "src/interfaces/external/curve/ICurveGauge.sol";
import {IERC7540Redeem} from "ERC-7540/interfaces/IERC7540.sol";

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
    //      Vault              Receiver   Amount
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
        
        // allow vault to pull shares
        IERC20(vault).safeIncreaseAllowance(vault, shares);

        // request redeem - send shares to vault
        IERC7540Redeem(vault).requestRedeem(shares, receiver, address(this));

        emit WithdrawalRequested(
            vault,
            IERC4626(vault).asset(),
            receiver,
            msg.sender,
            shares
        );
    }

    // anyone can claim for a receiver
    function claimWithdrawal(address vault, address receiver) external {
        uint256 amount = claimableAssets[vault][receiver];
        claimableAssets[vault][receiver] = 0;

        // claim asset with receiver shares
        IERC4626(vault).withdraw(amount, receiver, receiver);

        emit WithdrawalClaimed(vault, receiver, amount);
    }

    // anyone can fullfil a withdrawal for a receiver
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

        // fulfill redeem of pending shares for receiver
        uint256 assetAmount = IERC7540Redeem(vault).fulfillRedeem(shares, receiver);

        // assets are claimable now
        claimableAssets[vault][receiver] += assetAmount;

        emit WithdrawalFullfilled(vault, address(asset), receiver, shares);
    }

    error ZeroRequestShares();

    // only receiver is able to cancel a request
    function cancelRequest(address vault) external {
        uint256 sharesCancelled = requestShares[vault][msg.sender];

        if(sharesCancelled == 0)
            revert ZeroRequestShares();

        requestShares[vault][msg.sender] = 0;

        // cancel request and receive pending shares back
        IERC7540Redeem(vault).cancelRedeemRequest(msg.sender);

        emit WithdrawalCancelled(vault, msg.sender, sharesCancelled);
    }
}
