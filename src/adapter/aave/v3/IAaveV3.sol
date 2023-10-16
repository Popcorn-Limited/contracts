// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;

import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";

// Aave aToken (wrapped underlying)
interface IAToken is IERC20 {
  /**
   * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
   **/
  function UNDERLYING_ASSET_ADDRESS() external view returns (address);

  /**
   * @dev Returns the address of the incentives controller contract
   **/
  function getIncentivesController() external view returns (IAaveIncentives);

  function POOL() external view returns (address);
}

// Aave Incentives controller
interface IAaveIncentives {
  /**
   * @dev Returns list of reward token addresses for particular aToken.
   **/
  function getRewardsByAsset(address asset) external view returns (address[] memory);

  /**
   * @dev Claim all rewards for specified assets for user.
   **/
  function claimAllRewardsToSelf(
    address[] memory assets
  ) external returns (address[] memory rewardsList, uint256[] memory claimedAmount);
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
}

// Aave protocol data provider
interface IProtocolDataProvider {
  function getReserveTokensAddresses(address asset)
    external
    view
    returns (
      address aTokenAddress,
      address stableDebtTokenAddress,
      address variableDebtTokenAddress
    );
}
