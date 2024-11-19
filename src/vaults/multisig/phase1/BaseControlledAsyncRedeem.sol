// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {BaseERC7540} from "./BaseERC7540.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC7540Redeem} from "ERC-7540/interfaces/IERC7540.sol";

/// @notice Stores the requestBalance of a controller
struct RequestBalance {
    /// @notice The amount of shares that have been requested to be redeemed
    uint256 pendingShares;
    /// @notice The timestamp of the last redeem request (will be used to ensure timely fulfillment of redeem requests)
    uint256 requestTime;
    /// @notice The amount of shares that have been freed up by a fulfilled redeem request
    uint256 claimableShares;
    /// @notice The amount of assets that have been freed up by a fulfilled redeem request
    uint256 claimableAssets;
}

/**
 * @title   BaseControlledAsyncRedeem
 * @author  RedVeil
 * @notice  Abstract contract containing reusable logic for controlled async redeem flows
 * @dev     Based on https://github.com/ERC4626-Alliance/ERC-7540-Reference/blob/main/src/BaseControlledAsyncRedeem.sol
 */
abstract contract BaseControlledAsyncRedeem is BaseERC7540, IERC7540Redeem {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit assets into the vault
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @return shares The amount of shares received
     * @dev This function is synchronous and will revert if the vault is paused
     * @dev It will first use claimable balances of previous redeem requests before transferring assets from the sender
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Utilise claimable balance first
        uint256 assetsToTransfer = assets;
        RequestBalance storage currentBalance = requestBalances[msg.sender];
        uint256 pendingShares = currentBalance.claimableShares;

        if (currentBalance.claimableAssets > 0) {
            // Ensures we cant underflow when subtracting from assetsToTransfer
            uint256 claimableAssets = assetsToTransfer >
                currentBalance.claimableAssets
                ? currentBalance.claimableAssets
                : assetsToTransfer;

            // Modify the currentBalance state accordingly
            _withdrawClaimableBalance(claimableAssets, currentBalance);

            assetsToTransfer -= claimableAssets;
        }

        // Transfer the remaining assets from the sender
        if (assetsToTransfer > 0) {
            // Need to transfer before minting or ERC777s could reenter.
            SafeTransferLib.safeTransferFrom(
                asset,
                msg.sender,
                address(this),
                assetsToTransfer
            );
        }

        _mintWithClaimableBalance(pendingShares, shares, receiver);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Additional logic for inheriting contracts
        afterDeposit(assets, shares);
    }

    /**
     * @notice Mints shares from the vault
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     * @return assets The amount of assets deposited
     * @dev This function is synchronous and will revert if the vault is paused
     * @dev It will first use claimable balances of previous redeem requests before minting shares
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused returns (uint256 assets) {
        require(shares != 0, "ZERO_SHARES");
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        // Utilise claimable balance first
        uint256 assetsToTransfer = assets;
        RequestBalance storage currentBalance = requestBalances[msg.sender];
        uint256 pendingShares = currentBalance.claimableShares;

        if (currentBalance.claimableAssets > 0) {
            // Ensures we cant underflow when subtracting from assetsToTransfer
            uint256 claimableAssets = assetsToTransfer >
                currentBalance.claimableAssets
                ? currentBalance.claimableAssets
                : assetsToTransfer;

            // Modify the currentBalance state accordingly
            _withdrawClaimableBalance(claimableAssets, currentBalance);

            assetsToTransfer -= claimableAssets;
        }

        // Transfer the remaining assets from the sender
        if (assetsToTransfer > 0) {
            // Need to transfer before minting or ERC777s could reenter.
            SafeTransferLib.safeTransferFrom(
                asset,
                msg.sender,
                address(this),
                assetsToTransfer
            );
        }

        _mintWithClaimableBalance(pendingShares, shares, receiver);

        emit Deposit(msg.sender, receiver, assets, shares);

        // Additional logic for inheriting contracts
        afterDeposit(assets, shares);
    }

    /**
     * @notice Transfer shares to user using claimable shares prior to minting new ones
     * @param pendingShares The amount of claimableShares following a withdraw/redeem request
     * @param shares The user's entitled shares
     * @param receiver The user receiving shares
     */
    function _mintWithClaimableBalance(
        uint256 pendingShares,
        uint256 shares,
        address receiver
    ) internal {
        if (pendingShares >= shares) {
            // transfer exclusively pending shares
            SafeTransferLib.safeTransfer(
                ERC20(address(this)),
                receiver,
                shares
            );
        } else {
            // transfer eventual pending shares
            if (pendingShares > 0)
                SafeTransferLib.safeTransfer(
                    ERC20(address(this)),
                    receiver,
                    pendingShares
                );

            // mint the remaining
            _mint(receiver, shares - pendingShares);
        }
    }

    /**
     * @notice Withdraws assets from the vault which have beenpreviously freed up by a fulfilled redeem request
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param controller The controller to withdraw from
     * @return shares The amount of shares burned
     * @dev This function is asynchronous and will not revert if the vault is paused
     * @dev msg.sender must be the controller or an operator for the controller
     * @dev Requires sufficient claimableAssets in the controller's requestBalance
     */
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

        RequestBalance storage currentBalance = requestBalances[controller];
        shares = assets.mulDivUp(
            currentBalance.claimableShares,
            currentBalance.claimableAssets
        );

        // Modify the currentBalance state accordingly
        _withdrawClaimableBalance(assets, currentBalance);

        // Additional logic for inheriting contracts
        beforeWithdraw(assets, shares);

        // Burn controller's shares
        _burn(address(this), shares);

        // Transfer assets to the receiver
        SafeTransferLib.safeTransfer(asset, receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /**
     * @notice Modifies the currentBalance state to reflect a withdrawal of claimableAssets
     * @param assets The amount of assets to withdraw
     * @param currentBalance The requestBalance of the controller
     * @dev Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
     * while the claimable balance is reduced by a rounded up amount.
     */
    function _withdrawClaimableBalance(
        uint256 assets,
        RequestBalance storage currentBalance
    ) internal {
        uint256 sharesUp = assets.mulDivUp(
            currentBalance.claimableShares,
            currentBalance.claimableAssets
        );

        currentBalance.claimableAssets -= assets;
        currentBalance.claimableShares = currentBalance.claimableShares >
            sharesUp
            ? currentBalance.claimableShares - sharesUp
            : 0;
    }

    /**
     * @notice Redeems shares from the vault which have beenpreviously freed up by a fulfilled redeem request
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param controller The controller to redeem from
     * @return assets The amount of assets received
     * @dev This function is asynchronous and will not revert if the vault is paused
     * @dev msg.sender must be the controller or an operator for the controller
     * @dev Requires sufficient claimableShares in the controller's requestBalance
     */
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

        RequestBalance storage currentBalance = requestBalances[controller];
        assets = shares.mulDivDown(
            currentBalance.claimableAssets,
            currentBalance.claimableShares
        );

        // Modify the currentBalance state accordingly
        _redeemClaimableBalance(shares, currentBalance);

        // Additional logic for inheriting contracts
        beforeWithdraw(assets, shares);

        // Burn controller's shares
        _burn(address(this), shares);

        // Transfer assets to the receiver
        SafeTransferLib.safeTransfer(asset, receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /**
     * @notice Modifies the currentBalance state to reflect a withdrawal of claimableAssets
     * @param shares The amount of shares to redeem
     * @param currentBalance The requestBalance of the controller
     * @dev Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
     * while the claimable balance is reduced by a rounded up amount.
     */
    function _redeemClaimableBalance(
        uint256 shares,
        RequestBalance storage currentBalance
    ) internal {
        uint256 assetsUp = shares.mulDivUp(
            currentBalance.claimableAssets,
            currentBalance.claimableShares
        );

        currentBalance.claimableAssets = currentBalance.claimableAssets >
            assetsUp
            ? currentBalance.claimableAssets - assetsUp
            : 0;
        currentBalance.claimableShares -= shares;
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTNG LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @dev controller => requestBalance
    mapping(address => RequestBalance) public requestBalances;

    /**
     * @notice Returns the requestBalance of a controller
     * @param controller The controller to get the requestBalance of
     * @return requestBalance The requestBalance of the controller
     */
    function getRequestBalance(
        address controller
    ) public view returns (RequestBalance memory) {
        return requestBalances[controller];
    }

    /**
     * @notice Returns the requested shares for redeem that have not yet been fulfilled of a controller
     * @param controller The controller to get the pendingShares of
     * @return pendingShares The pendingShares of the controller
     */
    function pendingRedeemRequest(
        uint256,
        address controller
    ) public view returns (uint256) {
        return requestBalances[controller].pendingShares;
    }

    /**
     * @notice Returns the shares that have been freed up by a fulfilled redeem request of a controller
     * @param controller The controller to get the claimableShares of
     * @return claimableShares The claimableShares of the controller
     */
    function claimableRedeemRequest(
        uint256,
        address controller
    ) public view returns (uint256) {
        return requestBalances[controller].claimableShares;
    }

    /**
     * @notice Simulates a deposit into the vault and returns the amount of shares that would be received by the user
     * @param assets The amount of assets to deposit
     * @return shares The amount of shares that would be received by the user
     * @dev This function will return 0 if the vault is paused
     */
    function previewDeposit(
        uint256 assets
    ) public view virtual override returns (uint256) {
        return paused ? 0 : super.previewDeposit(assets);
    }

    /**
     * @notice Simulates a mint into the vault and returns the amount of assets required to mint the given amount of shares
     * @param shares The amount of shares to mint
     * @return assets The amount of assets required to mint the given amount of shares
     * @dev This function will return 0 if the vault is paused
     */
    function previewMint(
        uint256 shares
    ) public view virtual override returns (uint256) {
        return paused ? 0 : super.previewMint(shares);
    }

    /// @dev Previewing withdraw is not supported for async flows (we would require the controller to be known which we do not have in ERC4626)
    function previewWithdraw(
        uint256
    ) public pure virtual override returns (uint256) {
        revert("ERC7540Vault/async-flow");
    }

    /// @dev Previewing redeem is not supported for async flows (we would require the controller to be known which we do not have in ERC4626)
    function previewRedeem(
        uint256
    ) public pure virtual override returns (uint256 assets) {
        revert("ERC7540Vault/async-flow");
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the maximum amount of assets that can be deposited into the vault
     * @return assets The maxDeposit of the controller
     * @dev Will return 0 if the vault is paused
     */
    function maxDeposit(
        address
    ) public view virtual override returns (uint256) {
        return paused ? 0 : type(uint256).max;
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted into the vault
     * @return shares The maxMint of the controller
     * @dev Will return 0 if the vault is paused
     */
    function maxMint(address) public view virtual override returns (uint256) {
        return paused ? 0 : type(uint256).max;
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn from the vault
     * @param controller The controller to get the maxWithdraw of
     * @return assets The maxWithdraw of the controller
     * @dev This is simply the claimableAssets of the controller (i.e. the assets that have been freed up by a fulfilled redeem request)
     */
    function maxWithdraw(
        address controller
    ) public view virtual override returns (uint256) {
        return requestBalances[controller].claimableAssets;
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed from the vault
     * @param controller The controller to get the maxRedeem of
     * @return shares The maxRedeem of the controller
     * @dev This is simply the claimableShares of the controller (i.e. the shares that have been freed up by a fulfilled redeem request)
     */
    function maxRedeem(
        address controller
    ) public view virtual override returns (uint256) {
        return requestBalances[controller].claimableShares;
    }

    /*//////////////////////////////////////////////////////////////
                        REQUEST REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    event RedeemRequested(
        address indexed controller,
        address indexed owner,
        uint256 requestId,
        uint256 timestamp,
        address sender,
        uint256 shares
    );

    /**
     * @notice Requests a redeem of shares from the vault
     * @param shares The amount of shares to redeem
     * @param controller The user that will be receiving pending shares
     * @param owner The owner of the shares to redeem
     * @return requestId The requestId of the redeem request
     * @dev This redeem request is added to any pending redeem request of the controller
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external virtual returns (uint256 requestId) {
        return _requestRedeem(shares, controller, owner);
    }

    /// @dev Internal function to request a redeem
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

        // Transfer shares from owner to vault (these will be burned on withdrawal)
        SafeTransferLib.safeTransferFrom(this, owner, address(this), shares);

        // Update the controller's requestBalance
        RequestBalance storage currentBalance = requestBalances[controller];
        currentBalance.pendingShares += shares;
        currentBalance.requestTime = block.timestamp;

        emit RedeemRequested(
            controller,
            owner,
            REQUEST_ID,
            block.timestamp,
            msg.sender,
            shares
        );
        return REQUEST_ID;
    }

    /*//////////////////////////////////////////////////////////////
                        CANCEL REDEEM REQUEST LOGIC
    //////////////////////////////////////////////////////////////*/

    event RedeemRequestCanceled(
        address indexed controller,
        address indexed receiver,
        uint256 timestamp,
        uint256 shares
    );

    /**
     * @notice Cancels a redeem request of the controller
     * @param controller The controller to cancel the redeem request of
     * @dev This will transfer the pending shares back to the msg.sender
     */
    function cancelRedeemRequest(address controller) external virtual {
        return _cancelRedeemRequest(controller, msg.sender);
    }

    /**
     * @notice Cancels a redeem request of the controller
     * @param controller The controller to cancel the redeem request of
     * @param receiver The receiver of the pending shares
     * @dev This will transfer the pending shares back to the receiver
     */
    function cancelRedeemRequest(
        address controller,
        address receiver
    ) public virtual {
        return _cancelRedeemRequest(controller, receiver);
    }

    /// @dev Internal function to cancel a redeem request
    function _cancelRedeemRequest(
        address controller,
        address receiver
    ) internal virtual {
        require(
            controller == msg.sender || isOperator[controller][msg.sender],
            "ERC7540Vault/invalid-caller"
        );

        // Get the pending shares
        RequestBalance storage currentBalance = requestBalances[controller];
        uint256 shares = currentBalance.pendingShares;

        require(shares > 0, "ERC7540Vault/no-pending-request");

        // Transfer the pending shares back to the receiver
        SafeTransferLib.safeTransfer(ERC20(address(this)), receiver, shares);

        // Update the controller's requestBalance
        currentBalance.pendingShares = 0;
        currentBalance.requestTime = 0;

        emit RedeemRequestCanceled(
            controller,
            receiver,
            block.timestamp,
            shares
        );
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FULFILLMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    event RedeemRequestFulfilled(
        address indexed controller,
        address indexed fulfiller,
        uint256 timestamp,
        uint256 shares,
        uint256 assets
    );

    /**
     * @notice Fulfills a redeem request of the controller to allow the controller to withdraw their assets
     * @param shares The amount of shares to redeem
     * @param controller The controller to redeem for
     * @return assets The amount of assets claimable by the controller
     */
    function fulfillRedeem(
        uint256 shares,
        address controller
    ) external virtual returns (uint256) {
        uint256 assets = convertToAssets(shares);

        return _fulfillRedeem(assets, shares, controller);
    }

    /// @dev Internal function to fulfill a redeem request
    function _fulfillRedeem(
        uint256 assets,
        uint256 shares,
        address controller
    ) internal virtual returns (uint256) {
        if (assets == 0 || shares == 0) revert("ZERO_SHARES");

        RequestBalance storage currentBalance = requestBalances[controller];

        // Check that there are pending shares to fulfill
        require(
            currentBalance.pendingShares != 0 &&
                shares <= currentBalance.pendingShares,
            "ZERO_SHARES"
        );

        // Additional logic for inheriting contracts
        beforeFulfillRedeem(assets, shares);

        // Update the controller's requestBalance
        currentBalance.claimableShares += shares;
        currentBalance.claimableAssets += assets;
        currentBalance.pendingShares -= shares;

        // Reset the requestTime if there are no more pending shares
        if (currentBalance.pendingShares == 0) currentBalance.requestTime = 0;

        emit RedeemRequestFulfilled(
            controller,
            msg.sender,
            block.timestamp,
            shares,
            assets
        );

        return assets;
    }

    /// @dev Additional logic for inheriting contracts before fulfilling a redeem request
    function beforeFulfillRedeem(
        uint256 assets,
        uint256 shares
    ) internal virtual {}

    /*//////////////////////////////////////////////////////////////
                        ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return exists True if the contract supports the interface, false otherwise
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual override returns (bool) {
        return
            interfaceId == type(IERC7540Redeem).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
