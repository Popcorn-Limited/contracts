// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

// The assumption should be that we cant transfer the position to the vault since its in some form address bound
// TODO how to deal with different coll ratios per vault?
// Scenario:
// Vault A has a 200% coll ratio, Vault B has a 120% coll ratio
// This gives the strategy hook an overall coll ratio of 140%
// Now the strategy gets liquidated and Vault A gets punished even though it was Vault Bs fault
// Can we only punish Vault B while still keeping Vault A at 200% coll ratio?
contract AaveLooper {
    function init() external {}

    function assetBalanceByVault(
        address vault
    ) external view returns (uint256) {
        // 1. read vault position from state
        // 2. multiply position balance with multiplier or similar to get current assets
        // 3. return current assets
    }

    function depositHook() external {
        // 1. receive token
        // 2. check coll ratio
        // 3. adjust position based on coll ration and target coll ratio
        // IF coll ratio is too low
        // unwind()
        // 3.1. calculate how much to withdraw with new deposit
        // 3.2. (withdraw collateral)
        // 3.3. sell collateral for borrowed asset
        // 3.4. repay borrowed asset
        // 3.5. repeat until target coll ratio is reached
        // IF coll ratio is too high
        // lever()
        // 3.1. deposit new deposit
        // 3.2. borrow asset
        // 3.3. buy collateral
        // 3.4. deposit collateral
        // 3.5. repeat until target coll ratio is reached
        // 4. save new position in state
        // 5. notify success / failure
    }

    function withdrawHook() external {
        // 1. check assetBalanceByVault()
        // IF sufficient assets
        // 2. unwind sufficiently
        // 3. withdraw
        // 4. save new position in state
        // 5. notify success / failure
    }

    function manageHook() external {
        // 1. check coll ratio
        // 2. adjust position based on coll ration and target coll ratio
        // IF coll ratio is too low
        // unwind()
        // IF coll ratio is too high
        // lever()
    }
}
