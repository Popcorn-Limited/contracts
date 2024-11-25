To faciliate the fast changing needs of DeFi we create a vault that can grow with us into any direction we require. The goal is to create a vault that has absolute flexibility of what protocols to interact with and how but still remains easy to manage and save us on developing new strategies for each protocol out there.

For users the vault abstracts away the complexity of interacting with multiple protocols and allows them to deposit and withdraw with a single interface. They wont need to chase new protocols or rebalance as all this complexity is abstracted away.

## Architecture

The main contract is the `OracleVault` which uses a Gnosis-`Safe` to hold and manage assets. We use a `PushOracle` to keep track of the value of the assets held in the `Safe` and set the price of the vault shares.

The `OracleVault` follows the [ERC7540](https://eips.ethereum.org/EIPS/eip-7540) standard. Deposits are instantaneous but withdrawals are processed asynchronously.

The `PushOracle` is controlled by the `OracleVaultController` which has permissioned `keepers` to update the price of the `PushOracle`. Price updates are expected to happen in regular intervals. If a price update is significantly larger/smaller than the previous price we will update the price but pause the vault immediately to prevent any losses. The same goes for a drawdown from the latest high water mark. This ensures that price manipulations or temporary issues wont lead to a loss of funds for the vault or user.

The `Safe` is controlled by `managers` which can either be bots, ai agents or humans. All transactions are verified by a `TransactionGuard`-module and we have a seprate `SafeController`-module to remove malicious or inactive managers and even liquidate the `Safe` if needed. The `TransactionGuard` allows us to allow which contracts and functions `managers` can call. Later we will also add limits and decode and sanitize calls to increase security further.

`TransactionGuard` and `SafeController` both use a hook pattern to allow us to update and add additional functionality later.

![schema](images/schema.png)

## Sequence Diagrams

### Deposit

Deposits only have one state. On deposit the user sends funds to the `Vault` which in turn sends it to the `Safe`. The `Vault` than mints shares to the user.

```mermaid
sequenceDiagram
    participant User
    participant Vault
    participant Safe

    User->>+Vault: deposit(assets)

    Vault->>Vault: takeFees()

    Vault->>Safe: transfer(assets)

    Vault-->>User: mint(shares)

    deactivate Vault
```

### Withdraw

Withdrawals are processed asynchronously. Thefore we have multiple states of a withdrawal. 

First a user requests a withdrawal by sending shares to the `Vault`. This is the `pending`-state. In which a withdrawal was started but not yet completed.

In the second step that request has to get fulfilled. By sending assets to the `Vault` and burning the users shares. Now the user has `claimable assets`. This is the `fulfilled`-state. The user has their shares burned but their assets reserved though these still need to be claimed.

Lastly the user can call `withdraw()` on the `Vault` to get their funds. This is the `completed`-state. Here the user simply claims and receives their assets.


```mermaid
sequenceDiagram
    participant User
    participant Vault
    participant Safe

    User->>+Vault: requestRedeem(shares)

    Safe->>Vault: fulfillRedeem(assets)

    User->>+Vault: withdraw()
    Vault->>Vault: takeFees()
    Vault->>Vault: burn(shares)
    Vault-->>User: transfer(assets)
    deactivate Vault
```

## Scope

```
├── src
│   ├── vaults
│   │   └── multisig
│   │       └── phase1
│   │            ├── AsyncVault.sol
│   │            ├── BaseControlledAsyncRedeem.sol
│   │            ├── BaseERC7540.sol
│   │            └── OracleVault.sol
│   └── peripheral
|        └── oracles
|             ├── adapter
│             │   └── pushOracle
│             │       └── PushOracle.sol
│             └── OracleVaultController.sol
├── test
│   ├── vaults
│   │   └── multisig
│   │       └── phase1
│   │            ├── AsyncVault.t.sol
│   │            ├── BaseControlledAsyncRedeem.sol
│   │            ├── BaseERC7540.t.sol
│   │            └── OracleVault.t.sol
│   └── peripheral
│       ├── PushOracle.t.sol
│       └── OracleVaultController.t.sol
```

At this point we expect the manager to be a trusted permissioned actor which is why we wont include any contracts of the `SafeController`-module just yet.

For `TransactionGuard` we use the `ScopeGuard`-module by zodiac which has been extensively tested and is battle tested. https://github.com/gnosisguild/zodiac-guard-scope/tree/main

## Known Issues / Security Considerations

A lot of the security assumptions come down to proper configuration and key management / operational security.

A malicious owner of the `OracleVaultController` or `TransactionGuard` can rug the vault and the users funds. So we need to ensure the highest level of security to keep access to the keys as limited and safe as possible.

Additionally a poorly set up `TransactionGuard` can lead to a rug pull of the vault. Verifiying and maybe even auditing the deployment is crucial here.

Idle `managers` can also stale the withdrawal process since they will need to process and fulfill withdrawals. To incentivise fulfilling we can configure a `withdrawalIncentive` which will be paid out to the manager that fulfills the withdrawal.

Lastly `setLimits` on the `AsyncVault` can lock user deposits if set too high. This can lead to a situation where a user cannot withdraw their funds even though they deposited successfully. E.g. If there wasnt a `minAmount` initially and we set the `minAmount` to a value lower than the deposit amount of certain users they wont be able to withdraw without adding more funds to the vault which might not be possible.


## Deployment

To deploy a new OracleVault we need to set up an `PushOracle` and an `OracleVaultController`. The `PushOracle` needs to be nominated and the owner accepted by the `OracleVaultController`. This can be done using `VaultOracle.s.sol`.

Set up a Gnosis Safe via its app and add the agreed manager as a signer.

Now its time to deploy the `OracleVault`. The `OracleVault` needs to be added to the `OracleVaultController` and we should probably add a `keeper` on it aswell to update the price of the vault regularly. This can be done using `OracleVault.s.sol`.

To ensure the `VaultRouter` can pull funds from the Safe max-approve the `asset` to the `OracleVault`.

Lastly its recommended to set limits on the `OracleVaultController` after the vault gets deployed. To ensure that the vault wont get paused with every little price fluctuation. Simply use the script `SetVaultOracleLimits.s.sol` for it.

### Frontend Integration

To add the vault to the frontend add a new entry in `vaults/[chainId].json`. Make sure it has the the type `safe-vault-v1` and the `safe` address is correct. Than add it aswell to `vaults/tokens/[chainId].json`.

For the oracle to work you need to configure `vaults/safe/[chainId].json` and add all the assets we want to track with their price spreading. (Look at `vaults/safe/42161.json` for an example)

In `strategies/safe/[chainId].json` add the vault with all the strategies its allowed to use and their agreed allocations. (Look at `strategies/safe/42161.json` for an example)


## Further Improvements

- Add transaction verification and sanitization for all messages and transactions of the `Safe`. Managers should only be able to call previously whitelisted functions with appropriate parameters. This safeguards against rug pulls and allocations into assets that users didnt agree to.
- Futher improve and decentralie the Oracle. This could be done via zkTLS and the DeBank API to allow anyone to post the price of the vault via zkProofs.
- Add a liquidation mechanism for the `Safe` in case of drawdowns or problematic managers.
- Allow anyone to become a manager permissionlessly by simply providing a higher rate to the users and posting a certain security bond.