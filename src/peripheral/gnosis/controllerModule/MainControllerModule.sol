// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.12 <0.9.0;

import {Owned} from "src/utils/Owned.sol";
import {ISafe, Enum} from "safe-smart-account/interfaces/ISafe.sol";

struct ModuleCall {
    address to;
    uint256 value;
    bytes data;
    Enum.Operation operation;
}

/// @title Controller Module
/// @author RedVeil
contract ControllerModule is Owned {
    address internal constant SENTINEL_OWNERS = address(0x1);

    address public gnosisSafe;

    constructor(address gnosisSafe_, address owner_) Owned(owner_) {
        gnosisSafe = gnosisSafe_;
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTION LOGIC
    //////////////////////////////////////////////////////////////*/

    function executeModuleTransactions(ModuleCall[] memory calls) external {
        if (!isModule(msg.sender)) revert("Not a module");

        for (uint256 i; i < calls.length; i++) {
            bool success = ISafe(gnosisSafe).execTransactionFromModule(
                calls[i].to,
                calls[i].value,
                calls[i].data,
                calls[i].operation
            );
            if (!success) revert("Module transaction failed");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        MODULE LOGIC
    //////////////////////////////////////////////////////////////*/

    event AddedModule(address module);
    event RemovedModule(address module);

    address internal constant SENTINEL_MODULE = address(0x1);

    mapping(address => address) internal modules;
    uint256 internal moduleCount;

    /**
     * @notice Adds the module `module`
     * @dev This can only be done via a Safe transaction.
     * @param module New module address.
     */
    function addModule(address module) public onlyOwner {
        // module address cannot be null, the sentinel or the Safe itself.
        require(
            module != address(0) &&
                module != SENTINEL_MODULE &&
                module != address(this),
            "GS203"
        );
        // No duplicate modules allowed.
        require(modules[module] == address(0), "GS204");

        modules[module] = modules[SENTINEL_MODULE];
        modules[SENTINEL_MODULE] = module;

        moduleCount++;

        emit AddedModule(module);
    }

    /**
     * @notice Replaces the module `oldModule` in the Safe with `newModule`.
     * @dev This can only be done via a Safe transaction.
     * @param prevModule Owner that pointed to the owner to be replaced in the linked list
     * @param oldModule Owner address to be replaced.
     * @param newModule New owner address.
     */
    function swapModule(
        address prevModule,
        address oldModule,
        address newModule
    ) public onlyOwner {
        // Module address cannot be null, the sentinel or the Safe itself.
        require(
            newModule != address(0) &&
                newModule != SENTINEL_MODULE &&
                newModule != address(this),
            "GS203"
        );
        // No duplicate owners allowed.
        require(modules[newModule] == address(0), "GS204");
        // Validate oldModule address and check that it corresponds to module index.
        require(
            oldModule != address(0) && oldModule != SENTINEL_MODULE,
            "GS203"
        );

        modules[newModule] = modules[oldModule];
        modules[prevModule] = newModule;

        emit RemovedModule(oldModule);
        emit AddedModule(newModule);
    }

    /**
     * @notice Returns if `module` is an owner of the Safe.
     * @return Boolean if module is an owner of the Safe.
     */
    function isModule(address module) public view returns (bool) {
        return module != SENTINEL_MODULE && modules[module] != address(0);
    }

    /**
     * @notice Returns a list of Safe owners.
     * @return Array of Safe owners.
     */
    function getModules() public view returns (address[] memory) {
        address[] memory array = new address[](moduleCount);

        // populate return array
        uint256 index = 0;
        address currentModule = modules[SENTINEL_MODULE];
        while (currentModule != SENTINEL_MODULE) {
            array[index] = currentModule;
            currentModule = modules[currentModule];
            index++;
        }
        return array;
    }
}
