// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseVaultConfig} from "../BaseVault.sol";

interface ISingleStrategyVaultFactory {
    function updateVaultImplementation(address newVault) external;
    function deployVault(BaseVaultConfig memory config, address strategy) external;
}
