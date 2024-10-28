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
        if (multisig_ == address(0)) revert Misconfigured();

        multisig = params.multisig;
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
        if (!paused) _takeFees();

        SafeTransferLib.safeTransfer(asset, multisig, assets);
    }
}
