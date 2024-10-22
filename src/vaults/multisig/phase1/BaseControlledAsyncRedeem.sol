// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {BaseERC7540} from "./BaseERC7540.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC7540Redeem} from "ERC-7540/interfaces/IERC7540.sol";

abstract contract BaseControlledAsyncRedeem is BaseERC7540, IERC7540Redeem {
    using FixedPointMathLib for uint256;

    struct RequestBalance {
        uint256 pendingShares;
        uint256 requestTime;
        uint256 claimableShares;
        uint256 claimableAssets;
    }

    mapping(address => RequestBalance) internal requestBalances;

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTNG LOGIC
    //////////////////////////////////////////////////////////////*/

    function pendingRedeemRequest(
        uint256,
        address controller
    ) public view returns (uint256) {
        return requestBalances[controller].pendingShares;
    }

    function claimableRedeemRequest(
        uint256,
        address controller
    ) public view returns (uint256) {
        return requestBalances[controller].claimableShares;
    }

    function maxWithdraw(
        address controller
    ) public view virtual override returns (uint256) {
        return requestBalances[controller].claimableAssets;
    }

    function maxRedeem(
        address controller
    ) public view virtual override returns (uint256) {
        return requestBalances[controller].claimableShares;
    }

    // Preview functions always revert for async flows
    function previewWithdraw(
        uint256
    ) public pure virtual override returns (uint256) {
        revert("ERC7540Vault/async-flow");
    }

    function previewRedeem(
        uint256
    ) public pure virtual override returns (uint256 assets) {
        revert("ERC7540Vault/async-flow");
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice this deposit request is added to any pending deposit request
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external virtual returns (uint256 requestId) {
        return _requestRedeem(shares, controller, owner);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) internal returns (uint256 requestId) {
        require(
            owner == msg.sender || isOperator[owner][msg.sender],
            "ERC7540Vault/invalid-owner"
        );
        require(
            ERC20(address(this)).balanceOf(owner) >= shares,
            "ERC7540Vault/insufficient-balance"
        );
        require(shares != 0, "ZERO_SHARES");

        SafeTransferLib.safeTransferFrom(this, owner, address(this), shares);

        RequestBalance storage currentBalance = requestBalances[controller];
        currentBalance.pendingShares += shares;
        currentBalance.requestTime = block.timestamp;

        emit RedeemRequest(controller, owner, REQUEST_ID, msg.sender, shares);
        return REQUEST_ID;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FULFILLMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function fulfillRedeem(
        uint256 shares,
        address controller
    ) external virtual returns (uint256 assets) {
        assets = convertToAssets(shares);

        return _fulfillRedeem(shares, assets, controller);
    }

    function _fulfillRedeem(
        uint256 shares,
        uint256 assets,
        address controller
    ) internal returns (uint256 assets) {
        RequestBalance storage currentBalance = requestBalances[controller];
        require(
            currentBalance.pendingShares != 0 &&
                shares <= currentBalance.pendingShares,
            "ZERO_SHARES"
        );

        SafeTransferLib.safeTransferFrom(
            asset,
            msg.sender,
            address(this),
            assets
        );

        currentBalance.claimableShares += shares;
        currentBalance.claimableAssets += assets;
        currentBalance.pendingShares -= shares;

        if (currentBalance.pendingShares == 0) currentBalance.requestTime = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override returns (uint256 shares) {
        require(
            controller == msg.sender || isOperator[controller][msg.sender],
            "ERC7540Vault/invalid-caller"
        );
        require(assets != 0, "ZERO_ASSETS");

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        RequestBalance storage currentBalance = requestBalances[controller];
        shares = assets.mulDivDown(
            currentBalance.claimableShares,
            currentBalance.claimableAssets
        );
        uint256 sharesUp = assets.mulDivUp(
            currentBalance.claimableShares,
            currentBalance.claimableAssets
        );

        currentBalance.claimableAssets -= assets;
        currentBalance.claimableShares = currentBalance.claimableShares >
            sharesUp
            ? currentBalance.claimableShares - sharesUp
            : 0;

        // Just here to take fees
        beforeWithdraw(assets, shares);

        _burn(controller, shares);

        SafeTransferLib.safeTransfer(asset, receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override returns (uint256 assets) {
        require(
            controller == msg.sender || isOperator[controller][msg.sender],
            "ERC7540Vault/invalid-caller"
        );
        require(shares != 0, "ZERO_SHARES");

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        RequestBalance storage currentBalance = requestBalances[controller];
        assets = shares.mulDivDown(
            currentBalance.claimableAssets,
            currentBalance.claimableShares
        );
        uint256 assetsUp = shares.mulDivUp(
            currentBalance.claimableAssets,
            currentBalance.claimableShares
        );

        currentBalance.claimableAssets = currentBalance.claimableAssets >
            assetsUp
            ? currentBalance.claimableAssets - assetsUp
            : 0;
        currentBalance.claimableShares -= shares;

        // Just here to take fees
        beforeWithdraw(assets, shares);

        _burn(controller, shares);

        SafeTransferLib.safeTransfer(asset, receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual override returns (bool) {
        return
            interfaceId == type(IERC7540Redeem).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
