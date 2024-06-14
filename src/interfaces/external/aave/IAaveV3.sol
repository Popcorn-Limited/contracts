// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

import {IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {DataTypes} from "./DataTypes.sol";

interface IScaledBalanceToken {
    /**
     * @dev Returns the scaled balance of the user. The scaled balance is the sum of all the
     * updated stored balance divided by the reserve's liquidity index at the moment of the update
     * @param user The user whose balance is calculated
     * @return The scaled balance of the user
     *
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
     * @return The scaled total supply
     *
     */
    function scaledTotalSupply() external view returns (uint256);
}

// Aave aToken (wrapped underlying)
interface IAToken is IERC20, IScaledBalanceToken {
    /**
     * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
     *
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @dev Returns the address of the incentives controller contract
     *
     */
    function getIncentivesController() external view returns (IAaveIncentives);

    function POOL() external view returns (address);
}

// Aave Incentives controller
interface IAaveIncentives {
    /**
     * @dev Returns list of reward token addresses for particular aToken.
     *
     */
    function getRewardsByAsset(
        address asset
    ) external view returns (address[] memory);

    /**
     * @dev Returns list of reward tokens for all markets.
     *
     */
    function getRewardsList() external view returns (address[] memory);

    /**
     * @dev Claim all rewards for specified assets for user.
     *
     */
    function claimAllRewardsOnBehalf(
        address[] memory assets,
        address user,
        address to
    )
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmount);
}

// Aave lending pool interface
interface ILendingPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256);

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function flashLoan(
        address receiverAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory interestRateModes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function setUserUseReserveAsCollateral(
        address asset,
        bool useAsCollateral
    ) external;

    function setUserEMode(uint8 category) external;

    function getEModeCategoryData(
        uint8 id
    ) external returns (DataTypes.EModeData memory emodeData);

    function getUserEMode(address user) external returns (uint256);

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     *
     */
    function getReserveData(
        address asset
    ) external view returns (DataTypes.ReserveData2 memory);

    function getReserveNormalizedIncome(
        address asset
    ) external view returns (uint256);
}

// Aave protocol data provider
interface IProtocolDataProvider {
    function getReserveTokensAddresses(
        address asset
    )
        external
        view
        returns (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        );
}

interface IFlashLoanReceiver {
    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @param assets The addresses of the flash-borrowed assets
     * @param amounts The amounts of the flash-borrowed assets
     * @param premiums The fee of each flash-borrowed asset
     * @param initiator The address of the flashloan initiator
     * @param params The byte-encoded params passed when initiating the flashloan
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);

    function ADDRESSES_PROVIDER()
        external
        view
        returns (IPoolAddressesProvider);

    function POOL() external view returns (ILendingPool);
}

/**
 * @title IPoolAddressesProvider
 * @author Aave
 * @notice Defines the basic interface for a Pool Addresses Provider.
 */
interface IPoolAddressesProvider {
    /**
     * @notice Returns the id of the Aave market to which this contract points to.
     * @return The market id
     */
    function getMarketId() external view returns (string memory);

    /**
     * @notice Associates an id with a specific PoolAddressesProvider.
     * @dev This can be used to create an onchain registry of PoolAddressesProviders to
     * identify and validate multiple Aave markets.
     * @param newMarketId The market id
     */
    function setMarketId(string calldata newMarketId) external;

    /**
     * @notice Returns an address by its identifier.
     * @dev The returned address might be an EOA or a contract, potentially proxied
     * @dev It returns ZERO if there is no registered address with the given id
     * @param id The id
     * @return The address of the registered for the specified id
     */
    function getAddress(bytes32 id) external view returns (address);

    /**
     * @notice General function to update the implementation of a proxy registered with
     * certain `id`. If there is no proxy registered, it will instantiate one and
     * set as implementation the `newImplementationAddress`.
     * @dev IMPORTANT Use this function carefully, only for ids that don't have an explicit
     * setter function, in order to avoid unexpected consequences
     * @param id The id
     * @param newImplementationAddress The address of the new implementation
     */
    function setAddressAsProxy(
        bytes32 id,
        address newImplementationAddress
    ) external;

    /**
     * @notice Sets an address for an id replacing the address saved in the addresses map.
     * @dev IMPORTANT Use this function carefully, as it will do a hard replacement
     * @param id The id
     * @param newAddress The address to set
     */
    function setAddress(bytes32 id, address newAddress) external;

    /**
     * @notice Returns the address of the Pool proxy.
     * @return The Pool proxy address
     */
    function getPool() external view returns (address);

    /**
     * @notice Updates the implementation of the Pool, or creates a proxy
     * setting the new `pool` implementation when the function is called for the first time.
     * @param newPoolImpl The new Pool implementation
     */
    function setPoolImpl(address newPoolImpl) external;
}
