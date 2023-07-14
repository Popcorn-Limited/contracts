// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

contract Vault {
    function init() external {}

    function totalAssets() external view returns (uint256) {
        // 1. get adapter hook from state
        // 2. return adapterHook.assetBalanceByVault(address(this))
    }

    function deposit() external {
        // 1. get adapter,fee and strategy hooks from state
        // 2. receive asset
        // 3. calculate shares to return
        // 4. check for fee hook
        // IF it exists
        // 4.1. call feeHook.onDeposit()
        // 5. check for strategy hook
        // IF it exists
        // 5.1. call strategyHook.depositHook()
        // 6. call adapterHook.depositHook()
        // 6. mint shares
    }

    function withdraw() external {
        // 1. get adapter,fee and strategy hooks from state
        // 2. burn shares
        // 3. calculate assets to return
        // 4. check for fee hook
        // IF it exists
        // 4.1. call feeHook.onWithdraw()
        // 5. check for strategy hook
        // IF it exists
        // 5.1. call strategyHook.withdrawHook()
        // 6. call adapterHook.withdrawHook()
        // 7. return assets
    }

    function claim() external {
        // 1. adapter.claimHook()
        // 2. adjust index for all users to keep track of global rewards
        // 3. adjust rewardsClaimed for user
        // 4. send rewards to caller
    }

    function takeFees() external {
        // 1. check for fee hook
        // IF it exists
        // 2. call feeHook.onTakeFees()
    }

    function adjustHook() external {
        // 1. override hook config for key
    }
}
