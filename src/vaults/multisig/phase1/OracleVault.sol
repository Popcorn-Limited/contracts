// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {MultisigVault, InitializeParams} from "./MultisigVault.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";

contract OracleVault is MultisigVault {
    constructor(
        InitializeParams memory params,
        address oracle
    ) MultisigVault(params) {
        oracle = IPriceOracle(oracle);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    IPriceOracle public oracle;

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        return IPriceOracle(oracle).getQuote(totalSupply(), share, asset);
    }
}
