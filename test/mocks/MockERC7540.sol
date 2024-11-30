// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {AsyncVault, InitializeParams, Limits, Fees} from "src/vaults/multisig/phase1/AsyncVault.sol";

/**
 * @title   MockERC7540
 * @author  RedVeil
 * @notice  Mock ERC-7540 (https://eips.ethereum.org/EIPS/eip-7540) compliant async redeem vault
 */
contract MockERC7540 is AsyncVault {
    constructor(InitializeParams memory params) AsyncVault(params) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
