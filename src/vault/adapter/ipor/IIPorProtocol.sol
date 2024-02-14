// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;
import  "openzeppelin-contracts/token/ERC20/IERC20.sol";


/// @title Interface responsible for managing liquidity in the AMM Pools.
interface IAmmPoolsService {
    /// @notice A struct to represent a pool configuration in AmmPoolsService.
    struct AmmPoolsServicePoolConfiguration {
        /// @notice The address of the asset.
        address asset;
        /// @notice The number of decimals the asset uses.
        uint256 decimals;
        /// @notice The address of the ipToken associated with the asset.
        address ipToken;
        /// @notice The address of the AMM's storage contract.
        address ammStorage;
        /// @notice The address of the AMM's treasury contract.
        address ammTreasury;
        /// @notice The address of the asset management contract.
        address assetManagement;
        /// @notice Redeem fee rate, value represented in 18 decimals. 1e18 = 100%
        /// @dev Percentage of redeemed amount which stay in liquidity pool balance.
        uint256 redeemFeeRate;
        /// @notice Redeem liquidity pool max collateral ratio. Value describes what is maximal allowed collateral ratio for liquidity pool.
        /// @dev Collateral ratio is a proportion between liquidity pool balance and sum of all active swap collateral. Value represented in 18 decimals. 1e18 = 100%
        uint256 redeemLpMaxCollateralRatio;
    }

    /// @notice Emitted when `from` account provides liquidity (ERC20 token supported by IPOR Protocol) to AmmTreasury Liquidity Pool
    event ProvideLiquidity(
    /// @notice address that provides liquidity
        address indexed from,
    /// @notice Address that will receive ipTokens representing the provided liquidity.
        address indexed beneficiary,
    /// @notice AmmTreasury's address where liquidity is received
        address indexed to,
    /// @notice current ipToken exchange rate
    /// @dev value represented in 18 decimals
        uint256 exchangeRate,
    /// @notice amount of asset provided by user to AmmTreasury's liquidity pool
    /// @dev value represented in 18 decimals
        uint256 assetAmount,
    /// @notice amount of ipToken issued to represent user's share in the liquidity pool.
    /// @dev value represented in 18 decimals
        uint256 ipTokenAmount
    );

    /// @notice Emitted when `to` account executes redeem ipTokens
    event Redeem(
    /// @notice Address of the AMM Treasury contract
        address indexed ammTreasury,
    /// @notice AmmTreasury's address from which underlying asset - ERC20 Tokens, are transferred to `to` account
        address indexed from,
    /// @notice account where underlying asset tokens are transferred after redeem
        address indexed beneficiary,
    /// @notice ipToken exchange rate used for calculating `assetAmount`
    /// @dev value represented in 18 decimals
        uint256 exchangeRate,
    /// @notice underlying asset value calculated based on `exchangeRate` and `ipTokenAmount`
    /// @dev value represented in 18 decimals
        uint256 assetAmount,
    /// @notice redeemed IP Token value
    /// @dev value represented in 18 decimals
        uint256 ipTokenAmount,
    /// @notice underlying asset fee deducted when redeeming ipToken.
    /// @dev value represented in 18 decimals
        uint256 redeemFee,
    /// @notice net asset amount transferred from AmmTreasury to `to`/sender's account, reduced by the redeem fee
    /// @dev value represented in 18 decimals
        uint256 redeemAmount
    );

    /// @notice Gets the configuration of the pool for the given asset in AmmPoolsService.
    /// @param asset The address of the asset.
    /// @return The pool configuration.
    function getAmmPoolServiceConfiguration(
        address asset
    ) external view returns (AmmPoolsServicePoolConfiguration memory);

    /// @notice Providing USDT to the AMM Liquidity Pool by the sender on behalf of beneficiary.
    /// @dev Emits {ProvideLiquidity} event and transfers ERC20 tokens from the sender to the AmmTreasury,
    /// emits {Transfer} event from ERC20 asset, emits {Mint} event from ipToken.
    /// Transfers minted ipTokens to the beneficiary. Amount of transferred ipTokens is based on current ipToken exchange rate
    /// @param beneficiary Account receiving receive ipUSDT liquidity tokens.
    /// @param assetAmount Amount of ERC20 tokens transferred from the sender to the AmmTreasury. Represented in decimals specific for asset. Value represented in 18 decimals.
    function provideLiquidityUsdt(address beneficiary, uint256 assetAmount) external;

    /// @notice Providing USDC to the AMM Liquidity Pool by the sender on behalf of beneficiary.
    /// @dev Emits {ProvideLiquidity} event and transfers ERC20 tokens from the sender to the AmmTreasury,
    /// emits {Transfer} event from ERC20 asset, emits {Mint} event from ipToken.
    /// @param beneficiary Account receiving receive ipUSDT liquidity tokens.
    /// @param assetAmount Amount of ERC20 tokens transferred from the sender to the AmmTreasury. Represented in decimals specific for asset. Value represented in 18 decimals.
    function provideLiquidityUsdc(address beneficiary, uint256 assetAmount) external;

    /// @notice Providing DAI to the AMM Liquidity Pool by the sender on behalf of beneficiary.
    /// @dev Emits {ProvideLiquidity} event and transfers ERC20 tokens from the sender tothe AmmTreasury,
    /// emits {Transfer} event from ERC20 asset, emits {Mint} event from ipToken.
    /// @param beneficiary Account receiving receive ipUSDT liquidity tokens.
    /// @param assetAmount Amount of ERC20 tokens transferred from the sender to the AmmTreasury. Represented in decimals specific for asset. Value represented in 18 decimals.
    /// @dev Value represented in 18 decimals.
    function provideLiquidityDai(address beneficiary, uint256 assetAmount) external;

    /// @notice Redeems `ipTokenAmount` ipUSDT for underlying asset
    /// @dev Emits {Redeem} event, emits {Transfer} event from ERC20 asset, emits {Burn} event from ipToken.
    /// Transfers ERC20 tokens from the AmmTreasury to the beneficiary based on current exchange rate of ipUSDT.
    /// @param beneficiary Account receiving underlying tokens.
    /// @param ipTokenAmount redeem amount of ipUSDT tokens, represented in 18 decimals.
    /// @dev sender's ipUSDT tokens are burned, asset: USDT tokens are transferred to the beneficiary.
    function redeemFromAmmPoolUsdt(address beneficiary, uint256 ipTokenAmount) external;

    /// @notice Redeems `ipTokenAmount` ipUSDC for underlying asset
    /// @dev Emits {Redeem} event, emits {Transfer} event from ERC20 asset, emits {Burn} event from ipToken.
    /// Transfers ERC20 tokens from the AmmTreasury to the beneficiary based on current exchange rate of ipUSDC.
    /// @param beneficiary Account receiving underlying tokens.
    /// @param ipTokenAmount redeem amount of ipUSDC tokens, represented in 18 decimals.
    /// @dev sender's ipUSDC tokens are burned, asset: USDC tokens are transferred to the beneficiary.
    function redeemFromAmmPoolUsdc(address beneficiary, uint256 ipTokenAmount) external;

    /// @notice Redeems `ipTokenAmount` ipDAI for underlying asset
    /// @dev Emits {Redeem} event, emits {Transfer} event from ERC20 asset, emits {Burn} event from ipToken.
    /// Transfers ERC20 tokens from the AmmTreasury to the beneficiary based on current exchange rate of ipDAI.
    /// @param beneficiary Account receiving underlying tokens.
    /// @param ipTokenAmount redeem amount of ipDAI tokens, represented in 18 decimals.
    /// @dev sender's ipDAI tokens are burned, asset: DAI tokens are transferred to the beneficiary.
    function redeemFromAmmPoolDai(address beneficiary, uint256 ipTokenAmount) external;

    /// @notice Rebalances given assets between the AmmTreasury and the AssetManagement, based on configuration stored
    /// in the `AmmPoolsParamsValue.ammTreasuryAndAssetManagementRatio` field .
    /// @dev Emits {Deposit} or {Withdraw} event from AssetManagement depends on current asset balance on AmmTreasury and AssetManagement.
    /// @dev Emits {Transfer} from ERC20 asset.
    /// @param asset Address of the asset.
    function rebalanceBetweenAmmTreasuryAndAssetManagement(address asset) external;
}


/// @title Interface responsible for reading the AMM Pools state and configuration.
interface IAmmPoolsLens {
    /// @dev A struct to represent a pool configuration.
    /// @param asset The address of the asset.
    /// @param decimals The number of decimal places the asset uses.
    /// @param ipToken The address of the ipToken associated with the asset.
    /// @param ammStorage The address of the AMM's storage contract.
    /// @param ammTreasury The address of the AMM's treasury contract.
    /// @param assetManagement The address of the asset management contract.
    struct AmmPoolsLensPoolConfiguration {
        address asset;
        uint256 decimals;
        address ipToken;
        address ammStorage;
        address ammTreasury;
        address assetManagement;
    }

    /// @notice Gets Ipor Orale address
    function iporOracle() external view returns (address);

    /// @notice Retrieves the configuration of a specific asset's pool.
    /// @param asset The address of the asset.
    /// @return PoolConfiguration The pool's configuration.
    function getAmmPoolsLensConfiguration(address asset) external view returns (AmmPoolsLensPoolConfiguration memory);

    /// @notice Calculates the ipToken exchange rate.
    /// @dev The exchange rate is a ratio between the Liquidity Pool Balance and the ipToken's total supply.
    /// @param asset The address of the asset.
    /// @return uint256 The ipToken exchange rate for the specific asset, represented in 18 decimals.
    function getIpTokenExchangeRate(address asset) external view returns (uint256);
}


/// @title Interface of ipToken - Liquidity Pool Token managed by Router in IPOR Protocol for a given asset.
/// For more information refer to the documentation https://ipor-labs.gitbook.io/ipor-labs/automated-market-maker/liquidity-provisioning#liquidity-tokens
interface IIpToken is IERC20 {
    /// @notice Gets the asset / stablecoin address which is associated with particular ipToken smart contract instance
    /// @return asset / stablecoin address
    function getAsset() external view returns (address);

    /// @notice Gets the Token Manager's address.
    function getTokenManager() external view returns (address);

    /// @notice Sets token manager's address. IpToken contract Owner only
    /// @dev only Token Manager can mint or burn ipTokens. Function emits `TokenManagerChanged` event.
    /// @param newTokenManager Token Managers's address
    function setTokenManager(address newTokenManager) external;

    /// @notice Creates the ipTokens in the `amount` given and assigns them to the `account`
    /// @dev Emits {Transfer} from ERC20 asset and {Mint} event from ipToken
    /// @param account to which the created ipTokens were assigned
    /// @param amount volume of ipTokens created
    function mint(address account, uint256 amount) external;

    /// @notice Burns the `amount` of ipTokens from `account`, reducing the total supply
    /// @dev Emits {Transfer} from ERC20 asset and {Burn} event from ipToken
    /// @param account from which burned ipTokens are taken
    /// @param amount volume of ipTokens that will be burned, represented in 18 decimals
    function burn(address account, uint256 amount) external;

    /// @notice Emitted after the `amount` ipTokens were mint and transferred to `account`.
    /// @param account address where ipTokens are transferred after minting
    /// @param amount of ipTokens minted, represented in 18 decimals
    event Mint(address indexed account, uint256 amount);

    /// @notice Emitted after `amount` ipTokens were transferred from `account` and burnt.
    /// @param account address from which ipTokens are transferred to be burned
    /// @param amount volume of ipTokens burned
    event Burn(address indexed account, uint256 amount);

    /// @notice Emitted when Token Manager address is changed by its owner.
    /// @param newTokenManager new address of Token Manager
    event TokenManagerChanged(address indexed newTokenManager);

        /// @notice Returns the amount of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256);
}
