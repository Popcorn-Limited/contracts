// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

contract StargateLpStaking {
    function init() external {}

    function assetBalanceByVault(
        address vault
    ) external view returns (uint256) {
        // 1. read vault position from state
        // 2. multiply position balance with multiplier or similar to get current assets
        // 3. return current assets
    }

    function depositHook() external {
        // 1. receive asset
        // 2. deposit asset
        // 3. save new position in state
    }

    function strategyDepositHook() external {
        // 1. receive underlying
        // 2. deposit underlying for asset
        // 3. deposit asset
        // 3. adjust multiplier? <-- How to adjust this globally / only for specific vaults?
    }

    function withdrawHook() external {
        // 1. check assetBalanceByVault()
        // IF sufficient assets
        // 2. withdraw
        // 3. save new position in state
        // 4. notify success / failure
    }

    function claimHook() external {
        // 1. claim rewards
        // 2. adjust index for all vaults to keep track of global rewards
        // 3. adjust rewardsClaimed for vault
        // 4. send rewards to caller
        // 5. notify success / failure
    }
}
