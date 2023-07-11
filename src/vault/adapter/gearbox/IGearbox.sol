// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IPausable } from "../../../interfaces/IPausable.sol";

struct MultiCall {
  address target;
  bytes callData;
}

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


interface ICreditFacade {

  function openCreditAccount(
    uint256 amount,
    address onBehalfOf,
    uint16 leverageFactor,
    uint16 referralCode
  ) external payable;


  function openCreditAccountMulticall(
    uint256 borrowedAmount,
    address onBehalfOf,
    MultiCall[] calldata calls,
    uint16 referralCode
  ) external payable;


  function closeCreditAccount(
    address to,
    uint256 skipTokenMask,
    bool convertWETH,
    MultiCall[] calldata calls
  ) external payable;


  function liquidateCreditAccount(
    address borrower,
    address to,
    uint256 skipTokenMask,
    bool convertWETH,
    MultiCall[] calldata calls
  ) external payable;


  function liquidateExpiredCreditAccount(
    address borrower,
    address to,
    uint256 skipTokenMask,
    bool convertWETH,
    MultiCall[] calldata calls
  ) external payable;

  function increaseDebt(uint256 amount) external;

  function decreaseDebt(uint256 amount) external;

  function addCollateral(
    address onBehalfOf,
    address token,
    uint256 amount
  ) external payable;

  function multicall(MultiCall[] calldata calls) external payable;

  function hasOpenedCreditAccount(address borrower)
  external
  view
  returns (bool);

  function approve(
    address targetContract,
    address token,
    uint256 amount
  ) external;

  function approveAccountTransfer(address from, bool state) external;

  function enableToken(address token) external;

  function transferAccountOwnership(address to) external;

  function calcTotalValue(address creditAccount)
  external
  view
  returns (uint256 total, uint256 twv);


  function calcCreditAccountHealthFactor(address creditAccount)
  external
  view
  returns (uint256 hf);


  function isTokenAllowed(address token) external view returns (bool);

  function creditManager() external view returns (ICreditManagerV2);

  function transfersAllowed(address from, address to)
  external
  view
  returns (bool);

  function params()
  external
  view
  returns (
    uint128 maxBorrowedAmountPerBlock,
    bool isIncreaseDebtForbidden,
    uint40 expirationDate
  );


  function limits()
  external
  view
  returns (uint128 minBorrowedAmount, uint128 maxBorrowedAmount);

  function degenNFT() external view returns (address);

  function underlying() external view returns (address);
}


interface ICreditManagerV2 {

  function getCreditAccountOrRevert(address borrower)
  external
  view
  returns (address);

  function creditAccounts(address borrower) external view returns (address);
}

