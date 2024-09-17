// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

interface IControllerModule {
  function checkViolation(bytes memory data) external view returns(bool);

  function takeoverSafe(bytes memory data) external;
}

contract MultisigVaultController {
    constructor() {}

    /**
     * @notice Take over safe in case of rule violation
     * @param controllerModule module which checks and enforces rule violation
     * @param data data to prove rule violation
    */
    function takeoverSafe(address controllerModule, bytes memory data) external {
      require(isControllerModule[controllerModule], "")
      IControllerModule(controllerModule).takeoverSafe(data);
    }

    function executeTakeover(address[] memory newOwners,
        uint256 newThreshold) external {
          // Call MainControllerModule.takover
          // Transfer Security Deposit
        }

    
    /*//////////////////////////////////////////////////////////////
                            CONTROLLER MODULE LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(address => bool) public isControllerModule;

    function addControllerModule(address module) external onlyOwner {
        isModule[module] = true;
    }

    function removeControllerModule(address module) external onlyOwner {
        isModule[module] = false;
    }
}
