# Overview

This protocols goal is to make vault creation easy, safe and all without compromising on flexibility. It allows anyone to spin up their own Yearn in minutes.

**Vaults** can be created permissionlessly based on any underlying protocol and execute arbitrary strategies. 
It gives vault creators a quick and easy way to spin up any **Vault** they need and end users the guarantee that the created **Vault** will be safe. For some more context checkout the [whitepaper](./WhitePaper.pdf)

The protocol consists of 2 parts. The Vault Factory and the actual Vaults and Strategies.

In this audit we are gonna focus on the Vault contract, its abstracts and two strategies with their abstracts first. Later on we will have a second audit for the **VaultFactory** and **VaultRegistry** and potential other infrastructure contracts that will be required to deploy **Vaults** and **Strategies** ppermissionlessly.

## Vault & Strategy
-   **Vault:** A simple ERC-4626 implementation which allows the creator to add various types of fees and interact with other protocols via any ERC-4626 compliant **Adapter**. Fees and **Adapter** can be changed by the creator after a ragequit period.
-   **Strategy:** An immutable wrapper for existing contract to allow for ERC-4626 compatability. Optionally adapters can utilize a **Strategy** to perform various additional tasks besides simply depositing and withdrawing token from the wrapped protocol. PopcornDAO will collect management fees via these **Adapter**.


## Utility Contracts
Additionally we included 2 utility contracts that are used alongside the vault system.
-   **MultiRewardStaking:** A simple ERC-4626 implementation of a staking contract. A user can provide an asset and receive rewards in multiple tokens. Adding these rewards is done by the contract owner. They can be either paid out over time or instantly. Rewards can optionally also be vested on claim.
-   **MultiRewardEscrow:** Allows anyone to lock up and vest arbitrary tokens over a given time. Will be used mainly in conjuction with **MultiRewardStaking**.

All `Adapters`, `Vaults`, `Strategies` and `MultiRewardStaking` contracts are intended to be deployed as non-upgradeable clones.

# Security
There are multiple possible targets for attacks.
1. Draining user funds of endorsed vaults
2. Draining user funds with malicious vaults/adapter/strategies or staking contracts
3. Draining user funds with malicious assets
4. Grieving of management functions

### Dangerous Attacks
- Initial Deposit exploit (See the test in `YearnAdapter.t.sol`)
- Change `fees` of a vault to the max amount and change the `feeRecipient` to the attacker
- Exchange the adapter of a vault for a malicious adapter
- Nominate new `owner` of the `adminProxy` to change configurations or endorse malicious `templates`
## Grieving Attacks
- Set `harvestCooldown` too low and waste tokens and gas on harvests
- Add a multitude of templates to make identifing the legit template harder in the endorsement process
- `Reject` legit vaults / assets
- `Pause` vaults / adapters of other `creators`
- Predeploy deterministic proxies on other chains

Most of these attacks are only possible when the `VaultController` is misconfigured on deployment or its `owner` is compromised. The `owner` of `VaultController` should be a MultiSig which should make this process harder but nonetheless not impossible.

## Inflation Attack
EIP-4626 is vulnerable to the so-called [inflation attacks](https://ethereum-magicians.org/t/address-eip-4626-inflation-attacks-with-virtual-shares-and-assets/12677). This attack results from the possibility to manipulate the exchange rate and front run a victim’s deposit when the vault has low liquidity volume.  A similiar issue that affects yearn is already known. See Finding 3, "Division rounding may affect issuance of shares" in [Yearn's ToB audit](https://github.com/yearn/yearn-security/blob/master/audits/20210719_ToB_yearn_vaultsv2/ToB_-_Yearn_Vault_v_2_Smart_Contracts_Audit_Report.pdf) for the details. In order to combat this we are using virtual shares by a difference of 1e9. This approach was added in the latest release of openZeppelin. [OZ PR](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/3979)

# Tests
## Quickstart command
`export ETH_RPC_URL="<your-eth-rpc-url>" && export POLYGON_RPC_URL="<your-polygon-rpc-url>" && rm -Rf 2023-01-popcorn || true && git clone  https://github.com/code-423n4/2023-01-popcorn.git -j8 --recurse-submodules && cd 2023-01-popcorn && echo -e "ETH_RPC_URL=$ETH_RPC_URL\nPOLYGON_RPC_URL=$POLYGON_RPC_URL" > .env && foundryup && forge install && yarn install && forge test --no-match-contract 'Abstract' --gas-report`
## Prerequisites

-   [Node.js](https://nodejs.org/en/) v16.16.0 (you may wish to use [nvm][1])
-   [yarn](https://yarnpkg.com/)
-   [foundry](https://github.com/foundry-rs/foundry)


## Installing Dependencies

```
foundryup

forge install

yarn install
```

## Testing

```
Add RPC urls to .env

forge build

forge test --no-match-contract 'Abstract'
```
