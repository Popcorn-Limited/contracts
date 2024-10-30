// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AsyncVault, InitializeParams} from "./AsyncVault.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

contract OracleVault is AsyncVault {
    address public multisig;

    constructor(
        InitializeParams memory params,
        address oracle_,
        address multisig_
    ) AsyncVault(params) {
        if (multisig_ == address(0) || oracle_ == address(0))
            revert Misconfigured();

        multisig = multisig_;
        oracle = IPriceOracle(oracle_);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    IPriceOracle public oracle;

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        return oracle.getQuote(totalSupply, share, address(asset));
    }

    /*//////////////////////////////////////////////////////////////
                            ERC-4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function afterDeposit(uint256 assets, uint256) internal override {
        // deposit and mint already have the `whenNotPaused` modifier so we don't need to check it here
        _takeFees();

        SafeTransferLib.safeTransfer(asset, multisig, assets);
    }

    /*//////////////////////////////////////////////////////////////
                    BaseControlledAsyncRedeem OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function beforeFulfillRedeem(uint256 assets, uint256) internal override {
        SafeTransferLib.safeTransferFrom(
            asset,
            multisig,
            address(this),
            assets
        );
    }

    /*//////////////////////////////////////////////////////////////
                    AsyncVault OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function handleWithdrawalIncentive(
        uint256 fee,
        address feeRecipient
    ) internal override {
        if (fee > 0)
            SafeTransferLib.safeTransferFrom(
                asset,
                multisig,
                feeRecipient,
                fee
            );
    }
}
