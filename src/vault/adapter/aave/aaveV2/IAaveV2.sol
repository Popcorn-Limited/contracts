// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;

import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { DataTypes } from "./lib.sol";

interface IScaledBalanceToken {
  /**
   * @dev Returns the scaled balance of the user. The scaled balance is the sum of all the
   * updated stored balance divided by the reserve's liquidity index at the moment of the update
   * @param user The user whose balance is calculated
   * @return The scaled balance of the user
   **/
  function scaledBalanceOf(address user) external view returns (uint256);

  /**
   * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
   * @return The scaled total supply
   **/
  function scaledTotalSupply() external view returns (uint256);
}

// Aave aToken (wrapped underlying)
interface IAToken is IERC20, IScaledBalanceToken {
  /**
   * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
   **/
  function UNDERLYING_ASSET_ADDRESS() external view returns (address);

  /**
   * @dev Returns the address of the incentives controller contract
   **/
  function getIncentivesController() external view returns (IAaveMining);

  function POOL() external view returns (address);
}

// Aave liquidity mining interface
interface IAaveMining {
  function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);

  /*
   * LEGACY **************************
   * @dev Returns the configuration of the distribution for a certain asset
   * @param asset The address of the reference asset of the distribution
   * @return The asset index, the emission per second and the last updated timestamp
   **/
  function assets(address asset) external view returns (uint128, uint128, uint256);

  function REWARD_TOKEN() external view returns (address);
}

// Aave lending pool interface
interface ILendingPool {
  function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

  function withdraw(address asset, uint256 amount, address to) external returns (uint256);

  /**
   * @dev Returns the state and configuration of the reserve
   * @param asset The address of the underlying asset of the reserve
   * @return The state of the reserve
   **/
  function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);

  function getReserveNormalizedIncome(address asset) external view returns (uint256);
}

// Aave protocol data provider
interface IProtocolDataProvider {
  function getReserveTokensAddresses(
    address asset
  ) external view returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress);
}
