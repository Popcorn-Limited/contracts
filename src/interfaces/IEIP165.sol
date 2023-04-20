// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

interface IEIP165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
