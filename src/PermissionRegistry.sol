// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import { Owned } from "./utils/Owned.sol";

import {IPermissionRegistry} from "./base/interfaces/IPermissionRegistry.sol";

/**
 * @title   PermissionRegistry
 * @author  RedVeil
 * @notice  Allows the DAO to endorse and reject addresses for security purposes.
 */
contract PermissionRegistry is IPermissionRegistry, Owned { 
  /// @param _owner `AdminProxy`
  constructor(address _owner) Owned(_owner) {}

  /*//////////////////////////////////////////////////////////////
                          PERMISSIONS
    //////////////////////////////////////////////////////////////*/

  mapping(address => bool) public endorsed;

  event Endorsed(address indexed target, bool endorsed);

  function setEndorsements(address[] calldata targets, bool[] calldata endorsements) external onlyOwner {
    uint len = targets.length;
    for (uint i; i < len;) {
        endorsed[targets[i]] = endorsements[i];
        emit Endorsed(targets[i], endorsements[i]);
        unchecked {
            ++i;
        }
    }
  }
}