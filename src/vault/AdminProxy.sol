// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Owned} from "../utils/Owned.sol";

/**
 * @title   AdminProxy
 * @author  RedVeil
 * @notice  Ownes contracts in the vault ecosystem to allow for easy ownership changes.
 *
 * AdminProxy is controlled by VaultController. VaultController executes management functions on other contracts through `execute()`
 */
contract AdminProxy is Owned {
    constructor(address _owner) Owned(_owner) {}

    error UnderlyingError(bytes revertReason);

    /// @notice Execute arbitrary management functions.
    function execute(
        address target,
        bytes calldata callData
    ) external onlyOwner returns (bool success, bytes memory returnData) {
        (success, returnData) = target.call(callData);
        if (!success) revert UnderlyingError(returnData);
    }
}
