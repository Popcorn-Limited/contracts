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
contract CurveCompounder {
    function init() external {}

    function assetBalanceByVault(
        address vault
    ) external view returns (uint256) {
        // return 0 or fail
    }

    function depositHook() external {
        // 1. check config state for vault
        // 2. compound()
        // 2.1. claim rewards <-- would claim for all vaults using the adapter hook
        // 2.2. check min trade
        // 2.3 swap rewards for asset <-- would trade for all vaults using the adapter hook
        // 3. deposit asset <-- the adapter hook must report assets for the vault in this case
        // TODO how to decide to use depositHook or strategyDepositHook?
        // 4. notify success / failure
    }

    function withdrawHook() external {
        // 1. check adapterHook.assetBalanceByVault()
        // 2. compound()
        // IF sufficient assets
        // 3. withdraw
        // TODO how to decide to use withdrawHook or strategyWithdrawHook?
        // 4. save new position in adapterHook
        // 5. notify success / failure
    }

    function manageHook() external {
        // 1. check config state for vault
        // 2. compound()
        // 3. notify success / failure
    }
}
