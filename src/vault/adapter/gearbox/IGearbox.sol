// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IPausable } from "../../../interfaces/IPausable.sol";

interface IAddressProvider {
  function getContractsRegister() external view returns (address);
}

interface IContractRegistry {
  function pools(uint256 pid) external view returns (address);
}

interface IPoolService is IPausable {
  function dieselToken() external view returns (address);

  function underlyingToken() external view returns (address);

  function fromDiesel(uint256 amount) external view returns (uint256);

  function toDiesel(uint256 assets) external view returns (uint256);

  function expectedLiquidityLimit() external view returns (uint256);

  function expectedLiquidity() external view returns (uint256);

  function addLiquidity(uint256 amount, address onBehalfOf, uint256 referralCode) external;

  function removeLiquidity(uint256 amount, address to) external;
}
