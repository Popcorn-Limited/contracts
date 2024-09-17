All things Gnosis vault


### Abstract:
Create a Vault that allocates into multiple management multisigs. There must be guarantees for withdrawal and reasonable decentralalisation / permissionlessness.

Iteration 1 should have trust assumptions but the core infra should be build to replace these trust assumptions later via better modules.

![alt text](schema.png)


### Useful Links:
- Solv Audit - https://github.com/solv-finance/Audit/tree/main/Solv-Yield-Market
- Solv Guardian - https://github.com/solv-finance/solv-vault-guardian/blob/main/src/common/SolvVaultGuardianBase.sol
- Solv Markets - https://github.com/solv-finance/solv-contracts-v3/tree/main/markets
- Scope Guard - https://github.com/gnosisguild/zodiac-guard-scope/blob/main/contracts/ScopeGuard.sol

- Veda Decode And Sanitize - https://github.com/Se7en-Seas/boring-vault/tree/main/src/base/DecodersAndSanitizers


### TODO:
1. Vault
   1. Function to update multisigs and debt ceiling [x]
      1. (What happens if a multisig is used by multiple vaults?) <--- should be fine [x]
      2. (What happens if new debt ceiling is lower than current?) [x]
      3. (How to remove a multisig?) [x]
      4. (Linked list as withdrawalQueue) [x]
   2. Function for multisig to pull funds from vault [x]
   3. Deposit
      1. (Add autodeposit?) <--- managers should just pull funds [x]
      2. Add minDeposit [x]
   4. Withdrawal
      1. Cleanup functions
      2. Add withdrawal incentive [x]
      3. Add minWithdrawal [x]
      4. (Should we allow normal 4626 for instant withdrawals?) <--- managers should just push funds [x]
      5. (What happens if multiple manager react to a request? Race conditions bad?) [x]
      6. Add withdrawalQueue [x]
   5. Explore need for Pause state
      1. Do we also pause withdrawals?
      2. When does it get triggered?
      3. How does the withdrawal flow work when paused?
   6. Fees
      1. How to pay out managementFee / performanceFee to managers?
   7. Security Deposit
      1. How to raise the security deposit?
   8. Interest rate
      1. How to pay out interest rate?
      2. How to liquidate?
   9. Optional:
      1. Add time based redeem windows? (Solv)
      2. Add compliance hooks for tradFi?
      3. Since Multisigs take debt from the vault couldnt they pay interest on that? Which will be used as yield
2. Transaction Guard
   1. Add basic Scope Guard
      1. Whitelist only - Address + func selector [x]
      2. No native transfers [x]
      3. No change on guard or module
   2. Allow muliple guards to be added to the MainGuard based on target addres (or smth else) [x]
   3. (Add sample post-transaction-guard that checks TVL before and after)
   4. (Add sample sanitise transaction-guard (check input values))
3. Controller Module
   1. Modulerise Module (You should be able to add checks that can trigger the multisig takeover) [x]
   2. Add Checker contract to trigger when withdrawals arent honored
   3. Add Checker based on drawdown
   4. Add incentive for bots to call the takeover
   5. Add fallback manager
   6. How to liquidiate a multisig?
4. Oracle
   1. (Add oracle on expected yield, deposits/withdrawals and debt)
5. Additional
   1. Add safety deposit for managers
   2. Add V3-style logic for permissionless managers