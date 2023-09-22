// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import { IERC4626Upgradeable as IERC4626, IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {IBaseAdapter} from "./IBaseAdapter.sol";
import {BaseVaultConfig, VaultFees} from "../BaseVault.sol";



///// @notice Init data for a Vault
//struct VaultInitParams {
//  /// @Notice Address of the deposit asset
//  IERC20 asset;
//  /// @Notice Address of the adapter used by the vault
//  IERC4626 adapter;
//  /// @Notice Fees used by the vault
//  VaultFees fees;
//  /// @Notice Address of the recipient of the fees
//  address feeRecipient;
//  /// @Notice Maximum amount of assets that can be deposited
//  uint256 depositLimit;
//  /// @Notice Owner of the vault (Usually the submitter)
//  address owner;
//}


interface IVault is IERC4626 {
  error MaxError(uint256 amount);

  //  CONVERT SHARES & ASSETS
  function convertToAssets(uint256 shares) external view returns (uint256 assets);

  function owner() external view returns (address);

  // FEE VIEWS

  function accruedManagementFee() external view returns (uint256);

  function accruedPerformanceFee(uint256 performanceFee) external view returns (uint256);

  function highWaterMark() external view returns (uint256);

  function assetsCheckpoint() external view returns (uint256);

  function feesUpdatedAt() external view returns (uint256);

  function feeRecipient() external view returns (address);

  // USER INTERACTIONS

  function deposit(uint256 assets) external returns (uint256);

  function mint(uint256 shares) external returns (uint256);

  function withdraw(uint256 assets) external returns (uint256);

  function redeem(uint256 shares) external returns (uint256);

  function takeManagementAndPerformanceFees() external;

  // MANAGEMENT FUNCTIONS - STRATEGY

  function adapter() external view returns (address);

  function proposedAdapter() external view returns (address);

  function proposedAdapterTime() external view returns (uint256);

  function proposeAdapter(IERC4626 newAdapter) external;

  function changeAdapter() external;

  // MANAGEMENT FUNCTIONS - FEES

  function fees() external view returns (VaultFees memory);

  function proposedFees() external view returns (VaultFees memory);

  function proposedFeeTime() external view returns (uint256);

  function proposeFees(VaultFees memory) external;

  function changeFees() external;

  function setFeeRecipient(address feeRecipient) external;

  // MANAGEMENT FUNCTIONS - OTHER

  function quitPeriod() external view returns (uint256);

  function setQuitPeriod(uint256 _quitPeriod) external;

  function depositLimit() external view returns (uint256);

  function setDepositLimit(uint256 _depositLimit) external;

  function strategy() external view returns (IBaseAdapter);

  // HARVEST
  function harvest() external;

  function toggleAutoHarvest() external;

  function autoHarvest() external view returns (bool);

  function lastHarvest() external view returns (uint256);

  function harvestCooldown() external view returns (uint256);

  function setHarvestCooldown(uint256 harvestCooldown) external;

  // HARVEST PERFORMANCE
  function setPerformanceFee(uint256 fee) external;

  function performanceFee() external view returns (uint256);

  //  EIP-2612 STORAGE
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function nonces(address) external view returns (uint256);

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  // INITIALIZE

  function initialize(
    BaseVaultConfig memory _vaultConfig,
    address _strategy
  ) external;
}
