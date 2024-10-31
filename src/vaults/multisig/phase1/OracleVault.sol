// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AsyncVault, InitializeParams} from "./AsyncVault.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

/**
 * @title   OracleVault
 * @author  RedVeil
 * @notice  ERC-7540 (https://eips.ethereum.org/EIPS/eip-7540) compliant async redeem vault using a PushOracle for pricing and a Safe for managing assets
 * @dev     Oracle and safe security is handled in other contracts. We simply assume they are secure and don't implement any further checks in this contract
 */
contract OracleVault is AsyncVault {
    address public safe;

    /**
     * @notice Constructor for the OracleVault
     * @param params The parameters to initialize the vault with
     * @param oracle_ The oracle to use for pricing
     * @param safe_ The safe which will manage the assets
     */
    constructor(
        InitializeParams memory params,
        address oracle_,
        address safe_
    ) AsyncVault(params) {
        if (safe_ == address(0) || oracle_ == address(0))
            revert Misconfigured();

        safe = safe_;
        oracle = IPriceOracle(oracle_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    IPriceOracle public oracle;

    /// @notice Total amount of underlying `asset` token managed by the safe.
    function totalAssets() public view override returns (uint256) {
        return oracle.getQuote(totalSupply, share, address(asset));
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to handle the deposit and mint
    function afterDeposit(uint256 assets, uint256) internal override {
        // Deposit and mint already have the `whenNotPaused` modifier so we don't need to check it here
        _takeFees();

        // Transfer assets to the safe
        SafeTransferLib.safeTransfer(asset, safe, assets);
    }

    /*//////////////////////////////////////////////////////////////
                    BaseControlledAsyncRedeem OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to transfer assets from the safe to the vault before fulfilling a redeem
    function beforeFulfillRedeem(uint256 assets, uint256) internal override {
        SafeTransferLib.safeTransferFrom(
            asset,
            safe,
            address(this),
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                    AsyncVault OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Internal function to handle the withdrawal incentive
    function handleWithdrawalIncentive(
        uint256 fee,
        address feeRecipient
    ) internal override {
        if (fee > 0)
            // Transfer the fee from the safe to the fee recipient
            SafeTransferLib.safeTransferFrom(
                asset,
                safe,
                feeRecipient,
                fee
            );
    }
}
