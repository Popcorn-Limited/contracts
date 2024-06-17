# Overview
VaultCraft is a permissionless DeFi infrastructure for deploying custom yield strategies on any EVM chain within a few clicks. It also features a system to permissionlessly earn and direct rewards in the form of a perp call options token. 

VaultCraft consists of 3 different parts:
1. **VaultCraft Protocol** Our smart contracts deployed on multiple EVM-compatible chains. The Vault-System takes care of creating vaults that generate yield on a variety of assets while our Gauge-System is responsible for directing and earning additional rewards.
2. **Frontend** Built to simplify the interaction with the VaultCraft Protocol. It interacts with chains directly to fetch data and utilises the database for additional metadata.
3. **Database** The database contains metadata for vaults and assets. On top of that its also used to determine which vaults should be shown as flagship vaults and which vaults and gauges we decide to hide on the frontend. Additionally it stores APYs of vaults and gauges to reduce loading times of the frontend.

This document explains each of these parts in depth with the goal to get new contributors up to speed quickly. Lastly it also contains informations to various processes and tasks performed by VaultCraft to keep the protocol and frontend running.

# VaultCraft Protocol
The VaultCraft Protocol is build to easily deploy, manage and use Vaults. We utilise a vetokenomics system to incentive liquidity.

:::info
Vaults are capital pools that automatically generate yield based on opportunities present in the market. Vaults benefit users by socializing gas costs, automating the yield generation and rebalancing process, and automatically shifting capital as opportunities arise. End users also do not need to have proficient knowledge of the underlying protocols involved or DeFi, thus the Vaults represent a passive-investing strategy.
:::

## Vault-System 
![diagram vaults](https://hackmd.io/_uploads/HJL9sEreA.png)

The core vault system contains 2 types of contracts. 
1. **Vaults** Vaults are ERC-4626 compliant contracts which can be deployed easily by anyone to earn yield for users. Vaults utilize strategies (ERC-4626) to earn the yield in a variety of ways. The vault owner can swap our strategies when the old ones have errors or new opportunities arise without users needing to do anything. Additionally the vault owner can rebalance funds between multiple strategies to optimize yield and risk further. New strategies need to be first proposed and only take effect after a 3 day delay allowing users to exit the vault if they arent comfortable with the new strategies.
2. **Strategies** Strategies are also ERC-4626 compliant and interact with external protocols. They are used by vaults to interact with anything DeFi in a unified way. Strategies can range from simple wrapper contracts to complex strategies that perform leverage, restaking or active liquidity management. The strategy owner is responsible for adjusting any strategy relevant parameters and `harvesting` the strategy to perform actions such as compounding, adjusting leverage or staking. Strategies can have a performance fee that will be send to the `FeeRecipientProxy` in the form of strategy shares. The performance fee is calculated in an increase of `assets per share`. It will be only taken if the previews recorded `high water mark` is breached.

### Vault
Our Vaults are ERC-4626 implementations using multiple strategies to generate yield. Vaults can use 0+ strategies. A default index can be used to automatically deposit user funds in a selected strategy. Alternatively user deposits can simply transfer funds into the vault without depositing them instantly in a strategy. <br/>
The vault owner now has the ability to pull and push funds out of and into strategies that have been previously configured. By doing this they can capitalise by rate changes across any protocol of DeFi and rebalance user funds accordingly. A Vault could for example use USDC as its asset and have strategies configured to deposit USDC into Compound, Aave, Yearn and Flux. The vault owner can now allocate funds between all these protocols and rebalance instantly ones rates change.<br/>
Strategies can be swapped out aswell but only after a 3 day quit period has passed. The vault owner must first propose new strategies which every user can see and check. Than users have 3 days to leave the vault if they dont approve of the new strategies.<br/>

On deposit funds can be either just lie idle in the vault and be allocated later or be deposited automatically in one of the configured strategies. If so and which strategy will be used can be configured by the vault owner. <br/>
On withdrawal the vault first uses idle funds in the vault before withdrawing the necessary funds from the available strategies. The order of strategy withdrawals is determined by the `withdrawalQueue` which is also configurable by the vault owner.

Vaults inherit ERC-4626, ReentrancyGuard, Pausable and Owned from OZ. Vaults are usually deployed via a factory as Clones. Find the contract here: https://github.com/Popcorn-Limited/contracts/blob/main/src/vaults/MultiStrategyVault.sol <br/>


##### `initialize(IERC20 asset_, IERC4626[] calldata strategies_, uint256 depositLimit_, address owner)`
Initialise the vault after deployment.
- `asset_` Is the accounting asset used by the vault. All deposits and withdrawals will be done with this asset. `totalAssets` accounts for the balance of `asset_` controlled by the vault. This asset MUST be used by all strategies aswell. `asset` cant be changed later
- `strategies` Is an array of ERC-4626 strategies that have to be deployed beforehand. They will be utilized to interact with external protocols and earn the vault yield in a variety of ways. Its also possible to use an empty array. You might want to do this if there are no existing strategies for your asset yet but you still need a vault to incentivise it with a gauge and allow users to deposit via the frontend. `strategies` can be changed later.
- `depositLimit` If you want to cap the amount of assets that users can deposit into the vault control it with this parameter. If it should be uncapped set it to `type(uint256).max`. This can be changed later
- `owner` The owner of the contract has access to all management functions of the vault. Ownership can later be transfered.

##### `setDefaultDepositIndex(uint256 index) onlyOwner`
By changing the `defaultDepositIndex` the owner controls which strategy users will deposit into when calling `deposit` or `mint`. Set this index to either a strategy with high capacity or high yield so user funds dont lie idle in the vault. In case you dont want users to deposit into a strategy automatically set the `defaultDepositIndex` to `type(uint256).max`. Do this if gas costs for deposits are very high or if there are no strategies configured. 

##### `setWithdrawalQueue(uint256[] memory indexes) onlyOwner`
The `withdrawalQueue` controls in which order funds will be withdrawn from strategies in case a user withdrawal demands more assets than are available idle in the vault itself.

##### `proposeStrategies(IERC4626[] calldata strategies_) onlyOwner`
Use this if you want to add/remove or change the available strategies for this vault entirely. All new strategies need to utilise the same asset as the vault. Once new strategies have been proposed users have 3 days to withdraw before the proposed strategies can be enacted.

##### `changeStrategies()`
After new strategies have been proposed and the `quitPeriod` of 3 days has been passed anyone can enact the change of strategies. This will pull funds from all old strategies and 0 the approval to them. It will than store the new strategies and max-approve them. Afterwards the vault owner still needs to push the now idle funds into the new strategies.<br/>
!ATTENTION! Make sure the `defaultDepositIndex` is still set correctly after you swtiched the strategies.<br/>
!ATTENTION! Make sure the `withdrawalQueue` still works correctly with your new strategies and isnt out of bounds.

##### `pushFunds(Allocation[] calldata allocations) onlyOwner`
Deposit idle funds from the vault into strategies. Simply define each strategy you want to deposit into by their index and set the amount for it. If there arent enough funds idle you will need to pull funds first. 
```
struct Allocation {
    uint256 index;
    uint256 amount;
}
```

##### `pullFunds(Allocation[] calldata allocations) onlyOwner`
Withdraw funds from strategies similar to `pushFunds`. To rebalance usually one would first call `pullFunds` to free assets and than `pushFunds` to reallocate them.

##### `setDepositLimit(uint256 _depositLimit) onlyOwner`
Adjust the total amount of assets that can be held by the vault. `depositLimit` takes yield into account not just deposits.


### Strategies
Strategies adhere also to the ERC-4626 interface. They can either be externally deployed and managed or come from VaultCraft. VaultCraft strategies inherit ERC-4626, ReentrancyGuard, Pausable and Owned from OZ. They can have optionally a `harvest`-function to perform the strategies action. These actions might range from claiming rewards and compounding them, adjusting leverage or a huge variety more. Strategies can also have other management function for the strategy owner to adjust certain parameters. <br/>
Fees for the VaultCraft Protocol come from performance fees taken in strategies. They get minted as strategy shares and send to the `FeeRecipientProxy` whenever a previous `high water mark` of `assetsPerShare` was breached.

Since strategies variy wildly they cant really be explained here further. Simply check them out here: https://github.com/Popcorn-Limited/contracts/tree/main/src/vault/adapter

### Contribute
You can find all contracts for the vault-system here: https://github.com/Popcorn-Limited/contracts. <br/>
We use foundry for our entire setup.
Simply run `foundryup` and than `forge install` to install all dependencies. Than add the environment variables in `.env`.
Test contracts by running `forge build` and than `forge test`. For more informations about foundry check this out: https://book.getfoundry.sh/

## Gauge-System and VeTokenomics
VaultCraft uses the vetTokenomics model developed by [Curve](https://docs.curve.fi/curve_dao/liquidity-gauge-and-minting-crv/overview/) but with some additionally modifications pioniered by [Bunni](https://docs.bunni.pro/docs/intro). 

To incentivise liquidity on VaultCraft we automatically mint our reward token oVCX in a predetermined schedule over time. Initally the system minted 2M oVCX per week and reduces this rate by 2.71% per week. These oVCX can be exercised to buy VCX (paid for in WETH) from VaultCraft directly at a fixed 25% discount. Even though the total amount of new oVCX minted is predetermined users can still define how to split these rewards across the vaults of their choice. This happens by voting on Gauges (Which represent a specific Vault). 

Users can earn these oVCX rewards by staking their Vault shares into Gauges. Each Vault has their own specific Gauge. These Gauges accrue oVCX rewards over time which can be claimed by users based on their share of staked vault shares and their veVCX balance. We will get to the veVCX balance later.

Users have 10_000 votes which they can allocate. They might allocate all votes to one Gauge or split them however they like across multiple Gauges. These votes are than mutliplied with their veVCX balance to determine the final weight of their vote. Each `epoch` (which goes for 7 days) the system checks the weights of all votes and distributes the newly minted oVCX to their respective Gauges.

### veVCX
To aquire veVCX a user must pool WETH and VCX on the "80/20 VCX/WETH Pool" on Balancer to receive VCX-LP tokens. These can than be locked in the veVCX contract to receive veVCX. The amount of veVCX is determined by the lock time and the amount of LP-tokens locked. The maximum amount of time that one can lock LP-tokens for is 4 years. If a user locks for 4 years they will get the same amount of veVCX as the amount of LP-tokens locked. If they lock for 2 years they will only receive half etc. Its important to note that veVCX can not be transfered. Users can exit early though if they wish to resulting in a 25% penalty which will be send to the VaultCraft treasury.

:::info
The balance of veVCX decays linearly over the lock time until it reaches 0 at the end of a users lock time.
:::

The second benefit of owning veVCX besides more voting power is to boost gauges. As mentioned before the amount of rewards received from a given Gauge depends on the users share of gauge tokens and their veVCX balance. 

Curve modifies a liquidity provider's weight in a staking pool using the following formula:
$w=min⁡(l, 0.2l + 0.8L \frac{v}{V})$

$w$ is the weight, $l$ is the liquidity provided by the LP, $L$ is the total liquidity in the staking pool, $v$ is the amount of vetokens the LP has, $V$ is the total vetoken supply.

This means that if an LP has no vetokens, their liquidity is multiplied by 0.2x when deciding their weight in the staking pool. When they have enough vetokens, their weight goes from 0.2x to 1x, which translates into a $\frac{1}{0.2}=5x$ boost. In short a user must have the same share of veVCX as they have of a given Gauge. If a user owns 10% of the supply of Gauge A they also would need to own 10% of the total veVCX supply to get the maximum boost of 5x.

### Why oVCX?
Instead of using VCX as the reward token, Bunni uses call option tokens for VCX as the reward token. This has the benefit of enabling the protocol to accumulate a large cash reserve regardless of market conditions, as well as letting loyal holders buy VCX at a discount.

It’s best to illustrate this mechanism with an example. Let’s say the price of VCX is $100, and there is a call option token oVCX that gives its holder a perpetual right to buy VCX at 90% of the market price. The protocol issues 1 oVCX to a farmer Alice, who immediately exercises the option to buy 1 VCX for $90 and sell it on a DEX for $100. The tally of gains & losses are as follows:

    The protocol: -1 VCX, +$90
    The farmer Alice: +$10
    The DEX LPs: +1 VCX, -$100

Compare this to regular liquidity mining where the farmer doesn't pay anything to the protocol:

    The protocol: -1 VCX
    The farmer Alice: +$100
    The DEX LPs: +1 VCX, -$100

We have the following observations:

    Reallocation of cash: Using oVCX instead of VCX as the reward token effectively transfers cash gains from the farmers to the protocol, and the LPs for the token are not affected.
    Trading off incentivization efficiency for protocol cashflow: In our example, for each VCX token issued by the protocol, the farmer Alice only gets $10 of rewards instead of $100 in the case of regular liquidity mining, which is less efficient. The higher the discount is, the more efficient the incentivization is, but the less cash the protocol gets.
    Effectively a continuous token sale: Instead of giving away tokens for free in regular liquidity mining, we effectively turn incentivization into a continuous token sale at the current market price, which enables the protocol to potentially capture a lot more cash compared to a one-off token sale since the protocol would be selling tokens at a higher price when the market price goes up.

Furthermore, when option reward tokens are used in VaultCraft where the farmers are the same people as the token LPs, the tally becomes:

    The protocol: -1 VCX, +$90
    The farmer-LP: +1 VCX, -$90

which means that as the farmers receive oVCX rewards, they get the right to buy tokens from the protocol at a discount and increase their ownership. Over time, the protocol ownership will be transferred away from holders who aren’t providing liquidity and to the farmers who are providing liquidity, which optimizes the protocol ownership.

The tally also stays the same regardless of whether the farmer dumps the VCX gained from excercising the option on the market, since the farmer and the LP are one and the same. Because of this, we can assume that a lot of the farmers will not sell the VCX but lock it into vetoken and improve their yield.


### Contracts
Since we essentially forked Curves Gauge system their docs explain all contracts and processes perfectly. https://docs.curve.fi/curve_dao/liquidity-gauge-and-minting-crv/overview/<br/>
Simply skip the part about "CRV Inflation" and "Boosting". The rest is exactly the same.

Contracts for our gauge and option token system are split across a few repos.
- [Option Token](https://github.com/Popcorn-Limited/options-token)
- [Gauges](https://github.com/Popcorn-Limited/gauges)

We use foundry for our entire setup.
Simply run `foundryup` and than `forge install` to install all dependencies. Than add the environment variables in `.env`.
Test contracts by running `forge build` and than `forge test`. For more informations about foundry check this out: https://book.getfoundry.sh/

# Frontend
The frontend is split into two seperate repos. 
- The app lives at ....
- The landing lives at ....

Our tech-stack is:
- Next.js as the base
- Typescript as language
- Vercel for hosting
- TailwindCSS for styling
- Viem and Wagmi to interact with anything on-chain
- RainbowKit to connect with wallets
- Axios for async calls
- Yarn as package manager
- Jotai for global state

## Setup
- Install node 18+ and yarn
- Clone the repo
- Run `yarn` in root of the repo to install dependencies
- Add env variables in `.env`
- Run `yarn dev` to for a local instance
- Run `yarn build` to build the project

## App Overview
To explore the repo and make sense of it all start with `/pages` and explore the different pages their functionality. From their you will find the page specific components, states and lib functions used.

In `/pages/_app.tsx` You will find global provider and our RainbowKit + Wagmi setup.

Since most pages and components use similar state we fetch 90% of in `/components/common/Page.tsx` as this component wraps the content of every page. So no matter from where you enter the app all useEffects in `Page.tsx` will be called. This loads all user account data, vaults, assets, aave account data and more to be used by the rest of the app. We store them on atoms from jotai for global state to be reused on other components.

The file in which most of the fetching happens is `/lib/getTokenAndVaultsData.ts`. We utilise our database repo here to load in metadata for assets, vaults and gauges aswell as the daily apy data. Apy data is fetched from the DB and not live to speed up loading times.

ABI's and most addresses can be found in `/lib/constants`.

All atoms that can be used for global state are in `/lib/atoms`.


Most interfaces and types are stored in `/lib/types.ts`.

Styling is done largely in components with default tailwind classes. Everything custom is done in `/tailwind.config.js`.

`/public` Just holds some icons and images that we dont fetch from outside sources.

To build a new version simply push to main. Preview builds will automatically generated by vercel when pushing to any branch. You can find the link to the preview builds in each commit or PR.

## Landing Overview
The landing page is a pretty simple one page build in next.js and doesnt really require more explanation. 

# Database
We are utilising a public Github repo for most of our backend needs. Find it [here](https://github.com/Popcorn-Limited/defi-db). Available assets, vaults, strategies and their metadata is simply stored here and pulled by the frontend. This is done to keep the overhead of managing different services, infra and databases as low as possible. Additionally it allows anyone else to easily pull and add new data.

In `root` you find various scripts to fetch metadata which can be utilised by github actions to periodically update the db.

Everything related to vaults you will find in `/archive/vaults`. Each supported chain has a single json in the format `[chainId].json` containing the metadata of each vault which you can find below:

```typescript
interface Vault {
    address: Address;
    assetAddress: Address;
    chainId: number;
    fees: {
      deposit: number, // in 1e18
      withdrawal: number, // in 1e18
      management: number, // in 1e18
      performance: number // in 1e18
    };
    type: "single-asset-vault-v1" | "single-asset-lock-vault-v1" | "multi-strategy-vault-v1";
    name?:string; // Will be used instead of the vault token name if set
    description?: string;
    creator: Address; // vault owner
    strategies: Address[];
    labels?: "Experimental" | "Deprecated" | "New"[];
}
```

Additionally in `/archive/vaults/tokens` you will find one json per supported chain that holds the basic token informations of each Vault. In order to display a vault properly on the VaultCraft frontend each vault must have metadata in the DB in `/archive/vaults/[chainId].json`,`/archive/vaults/tokens/[chainId].json`, their asset must be in `/archive/assets/tokens/[chainId].json` and their strategy must be included in `/archive/descriptions/strategies/[chainId].json`. 

All tokens in the DB share the same format:
```typescript
interface Token {
    address: Address;
    name: string;
    symbol: string;
    decimals: number;
    logoURI: string;
    chainId: number
}
```
The basic metadata of any asset that could be used by the frontend is stored in `/archive/assets/tokens/[chainId].json`. They follow the same interface as shown above.

TODO strategy interface

All vaults in our DB get shown on `app.vaultcraft.io/vaults/all` though there is no direct link to find this page besides the URL. We also promote certain vaults that we call "flagship vaults" which will than be promoted in the app and shown on our main page at `app.vaultcraft.io/vaults`. Which vaults get displayed here is controlled via json files in `/archive/vaults/flagship/[chainId].json`.

We also have the ability to hide vaults and gauges from the frontend. These addresses are in `/archive/gauges/hidden/[chainId].json` or `archive/vaults/hidden/[chainId].json`.

# Processes / Tasks
In this section we will discuss all processes necessary to run the VaultCraft protocol and frontend. Some processes only need to be occassionally others regularly. 

:::danger
In order to make sure that the oVCX oracle works correctly we currently need to perform the "Adjust Oracle"-task daily if the current strike price isnt accurate. The OptionToken-Oracle only starts working properly automatically once we had 1024 trades in the Pool. Until than we need to perform this task.
:::

:::warning
In order to make sure that the exercise contracts on each chain have enough VCX we need to perform the "Fund oVCX"-task weekly. Additionally we need to perform the "Transmit Rewards"-task weekly to send rewards to other chains than Ethereum.
:::

:::info
Each strategies owner must make sure that the "Harvest and Manage Strategies"-task is performed in a regular interval to make sure the strategies perform correctly. The interval here depends on each strategy and the current market environment.
:::

## Regular Tasks
### Adjust Oracle
To make sure the oVCX exercise price is correct check the exercise price daily. If its far off `VCX-Price * 0.75` adjust it. The oVCX exercise price is denominated in ETH. In order to adjust the exercise price perform these steps:
1. Get the USD-Price of 1 VCX ![image](https://hackmd.io/_uploads/Bk1bge3xC.png)
2. Get the amount of ETH for that USD-Value ![image](https://hackmd.io/_uploads/HJUVgx2xR.png)
3. Multiply the ETH amount with 1e18 ![image](https://hackmd.io/_uploads/rko6xghgC.png)
4. Multiply the result with 0.75 to get the actual exercise price in ETH. ![image](https://hackmd.io/_uploads/H1VZZx2lR.png)
5. Connect with the Gnosis Multisig at https://app.vaultcraft.io/manage/misc
6. Adjust the `minPrice` with the result of step 4 ![image](https://hackmd.io/_uploads/H1mBWe2eC.png)
7. Sign and execute the transaction.

### Fund oVCX
TODO (Build management frontend first)
1. Check Exercising balances
2. Bridge VCX if necessary
3. Fund exercising contracts

### Transmit Rewards
Before a new epoch transmit rewards for the previous epoch to all L2 gauges. You can simply include all L2 gauges or simply the ones which received voting weight.
1. Connect with the Gnosis Multisig at https://app.vaultcraft.io/manage/misc
2. Enter the addresses of all the relevant L2 Gauges seperated by a comma
![image](https://hackmd.io/_uploads/ry1xgX6gC.png)
3. Sign and execute the transaction.

### Harvest and Manage Strategies
Each strategy manager must keep an eye on their strategies if they require calls to the `harvest`-function or other parameter adjustments. Unfortunately the strategies are too different that we dont have a frontend for them yet. Its best to keep a list of all strategies controlled by you and regularly check their state on etherscan. Adjustments can be done with scripts in the contracts repo or simply directly in etherscan. Check out [cast send](https://book.getfoundry.sh/reference/cast/cast-send) to adjust strategies directly in the terminal or [forge scripts](https://book.getfoundry.sh/tutorials/solidity-scripting) to write scripts in solidity to adjust strategies.

## Deployment
### Deploy Vault
1. Select asset + strategies
2. (deploy strategies)
3. deploy vault via script (utilising factory)

### Deploy Strategy
1. Decide which strategy to deploy with what asset
2. Read the `setHarvestValues`-function to understand the input values needed
3. Navigate to `/scripts/Deploy[StrategyName].s.sol` in the contracts repo and edit the deploy script
4. Open `package.json` if you need to edit the rpc url
5. Run `yarn deploy:[StrategyName]` to deploy the strategy

### Deploy a new Gauge
TODO - copy ruhums notes

### Deploy on a new chain
1. Deploy FeeRecipient using salt
2. Deploy vault factory
3. TODO - copy ruhums notes


## Frontend Management
### Add/Edit Vault for frontend
0. Read more about the DB and schemas in the "Database"-chapter above
1. Clone or fork https://github.com/Popcorn-Limited/defi-db.
2. Edit `/archive/vaults/[chainId].json` and `/archive/vaults/tokens/[chainId].json` to add/edit the vault itself.
3. Edit `/archive/descriptions/strategies/[chainId].json` if the vault uses a new strategy that isnt in the DB yet.
4. Make sure the vaults asset is included in `/archive/assets/tokens/[chainId].json`. Optionally upload an asset icon to `/archive/assets/icons` if its not already hosted somewhere else.
5. Submit PR (and reach out to a dev to review and merge it)

### Add/Edit Asset for frontend
0. Read more about the DB and schemas in the "Database"-chapter above
1. Clone or fork https://github.com/Popcorn-Limited/defi-db.
2. Edit `/archive/assets/tokens/[chainId].json`. Optionally upload an asset icon to `/archive/assets/icons` if its not already hosted somewhere else.
3. Submit PR (and reach out to a dev to review and merge it)

### Add/Remove flagship vaults
0. Read more about the DB and schemas in the "Database"-chapter above
1. Clone or fork https://github.com/Popcorn-Limited/defi-db.
2. Edit `/archive/vaults/flagship/[chainId].json` to add or remove a flagship vault. This vault MUST be in stored in the DB already.
5. Submit PR (and reach out to a dev to review and merge it)

### Hide Vaults and Gauges
0. Read more about the DB and schemas in the "Database"-chapter above
1. Clone or fork https://github.com/Popcorn-Limited/defi-db.
2. Edit `/archive/vaults/hidden/[chainId].json` to hide vaults or `/archive/gauges/hidden/[chainId].json` to hide gauges.
5. Submit PR (and reach out to a dev to review and merge it)

### How to add a new protocol
TODO

## Fees
### Take Strategy fees
TODO 

### Deal with fees
All fees will be accumulated in the [FeeRecipientProxy](https://github.com/Popcorn-Limited/contracts/blob/main/src/vault/FeeRecipientProxy.sol). Strategy and Vault shares will need to be redeemed later to get the actual assets. In order to pull funds the FeeRecipientProxy-owner will need to approve the asset they want to utilise in the FeeRecipient for the account that wants to pull them. 
1. Check the token balance you want to pull and if its approved
2. Connect with the owner address on the FeeRecipient using etherscan and call `approveToken` with the token address you want to pull
3. Connect with the owner address on the token using etherscan and call `transferFrom`. (Owner is FeeRecipient address, receiver is the user of the fees)


## Other
### Writing a new strategy
COMING SOON