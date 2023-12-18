// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {IERC20MetadataUpgradeable as IERC20Metadata} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

interface IMetaPool {
  function swapwNEARForstNEAR(uint256 _amount) external;
  function swapstNEARForwNEAR(uint256 _amount) external;
  function stNearPrice() external view returns(uint256);
  function wNear() external view returns (IERC20Metadata);
  function stNear() external view returns (IERC20Metadata);
  function wNearSwapFee() external view returns (uint16);
  function stNearSwapFee() external view returns (uint16);
}