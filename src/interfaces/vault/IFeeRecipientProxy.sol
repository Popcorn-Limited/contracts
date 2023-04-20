// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IFeeRecipientProxy {
  function approveToken(IERC20[] memory tokens) external;

  function voidTokenApproval(IERC20[] memory tokens) external;
}
