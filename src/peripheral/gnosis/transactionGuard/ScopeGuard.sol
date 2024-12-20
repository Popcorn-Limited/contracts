// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.12 <0.9.0;

import {BaseGuard} from "safe-smart-account/examples/guards/BaseGuard.sol";
import {Enum} from "safe-smart-account/libraries/Enum.sol";
import {Owned} from "src/utils/Owned.sol";

/// @notice Target struct to store allowed/disallowed targets and functions
struct Target {
    /// @notice Whether the target is allowed
    bool allowed;
    /// @notice Whether the target only has certain functions allowed
    bool scoped;
    /// @notice Whether delegate calls to the target are allowed
    bool delegateCallAllowed;
    /// @notice Whether fallback calls to the target are allowed
    bool fallbackAllowed;
    /// @notice Whether ETH can be sent to the target
    bool valueAllowed;
    /// @notice Mapping of allowed function signatures for scoped targets
    mapping(bytes4 => bool) allowedFunctions;
}

/**
 * @title   ScopeGuard
 * @author  RedVeil
 * @notice  Transaction guard that checks if a transaction is allowed based on the target and function
 * @notice  Based on Zodiac's implementation https://github.com/gnosisguild/zodiac-guard-scope/tree/main
 */
contract ScopeGuard is BaseGuard, Owned {
    constructor(address owner_) Owned(owner_) {}

    // solhint-disallow-next-line payable-fallback
    fallback() external {
        // We don't revert on fallback to avoid issues in case of a Safe upgrade
        // E.g. The expected check method might change and then the Safe would be locked.
    }

    /*//////////////////////////////////////////////////////////////
                        GUARD LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called by the Safe contract before a transaction is executed.
     * @param to Destination address of Safe transaction.
     * @param value Ether value of Safe transaction.
     * @param data Data payload of Safe transaction.
     * @param operation Operation type of Safe transaction.
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        // solhint-disallow-next-line no-unused-vars
        address payable,
        bytes memory,
        address
    ) external override {
        _checkTransaction(to, value, data, operation);
    }

    /**
     * @notice Checks the module transaction details.
     * @dev The function needs to implement module transaction validation logic.
     * @param to The address to which the transaction is intended.
     * @param value The value of the transaction in Wei.
     * @param data The transaction data.
     * @param operation The type of operation of the module transaction.
     * @return moduleTxHash The hash of the module transaction.
     */
    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address
    ) external override returns (bytes32 moduleTxHash) {
        _checkTransaction(to, value, data, operation);
    }

    /// @dev Internal function to check transactions
    function _checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) internal view {
        require(
            operation != Enum.Operation.DelegateCall ||
                allowedTargets[to].delegateCallAllowed,
            "Delegate call not allowed to this address"
        );
        require(allowedTargets[to].allowed, "Target address is not allowed");
        if (value > 0) {
            require(
                allowedTargets[to].valueAllowed,
                "Cannot send ETH to this target"
            );
        }
        if (data.length >= 4) {
            require(
                !allowedTargets[to].scoped ||
                    allowedTargets[to].allowedFunctions[bytes4(data)],
                "Target function is not allowed"
            );
        } else {
            require(data.length == 0, "Function signature too short");
            require(
                !allowedTargets[to].scoped ||
                    allowedTargets[to].fallbackAllowed,
                "Fallback not allowed for this address"
            );
        }
    }

    /// @dev Empty implementation
    function checkAfterExecution(bytes32, bool) external override {}

    /// @dev Empty implementation
    function checkAfterModuleExecution(bytes32, bool) external override {}

    /*//////////////////////////////////////////////////////////////
                        VIEW LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns bool to indicate if an address is an allowed target.
     * @param target Address to check.
     */
    function isAllowedTarget(address target) public view returns (bool) {
        return (allowedTargets[target].allowed);
    }

    /**
     * @notice Returns bool to indicate if an address is scoped.
     * @param target Address to check.
     */
    function isScoped(address target) public view returns (bool) {
        return (allowedTargets[target].scoped);
    }

    /**
     * @notice Returns bool to indicate if fallback is allowed to a target.
     * @param target Address to check.
     */
    function isfallbackAllowed(address target) public view returns (bool) {
        return (allowedTargets[target].fallbackAllowed);
    }

    /**
     * @notice Returns bool to indicate if ETH can be sent to a target.
     * @param target Address to check.
     */
    function isValueAllowed(address target) public view returns (bool) {
        return (allowedTargets[target].valueAllowed);
    }

    /**
     * @notice Returns bool to indicate if a function signature is allowed for a target address.
     * @param target Address to check.
     * @param functionSig Signature to check.
     */
    function isAllowedFunction(
        address target,
        bytes4 functionSig
    ) public view returns (bool) {
        return (allowedTargets[target].allowedFunctions[functionSig]);
    }

    /**
     * @notice Returns bool to indicate if delegate calls are allowed to a target address.
     * @param target Address to check.
     */
    function isAllowedToDelegateCall(
        address target
    ) public view returns (bool) {
        return (allowedTargets[target].delegateCallAllowed);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev target => Target
    mapping(address => Target) public allowedTargets;

    event SetTargetAllowed(address target, bool allowed);
    event SetTargetScoped(address target, bool scoped);
    event SetFallbackAllowedOnTarget(address target, bool allowed);
    event SetValueAllowedOnTarget(address target, bool allowed);
    event SetDelegateCallAllowedOnTarget(address target, bool allowed);
    event SetFunctionAllowedOnTarget(
        address target,
        bytes4 functionSig,
        bool allowed
    );

    /**
     * @notice Set whether or not calls can be made to an address.
     * @param target Address to be allowed/disallowed.
     * @param allow Bool to allow (true) or disallow (false) calls to target.
     * @dev Only callable by owner.
     */
    function setTargetAllowed(address target, bool allow) public onlyOwner {
        allowedTargets[target].allowed = allow;
        emit SetTargetAllowed(target, allowedTargets[target].allowed);
    }

    /**
     * @notice Set whether or not delegate calls can be made to a target.
     * @param target Address to which delegate calls should be allowed/disallowed.
     * @param allow Bool to allow (true) or disallow (false) delegate calls to target.
     * @dev Only callable by owner.
     */
    function setDelegateCallAllowedOnTarget(
        address target,
        bool allow
    ) public onlyOwner {
        allowedTargets[target].delegateCallAllowed = allow;
        emit SetDelegateCallAllowedOnTarget(
            target,
            allowedTargets[target].delegateCallAllowed
        );
    }

    /**
     * @notice Sets whether or not calls to an address should be scoped to specific function signatures.
     * @param target Address to be scoped/unscoped.
     * @param scoped Bool to scope (true) or unscope (false) function calls on target.
     * @dev Only callable by owner.
     */
    function setScoped(address target, bool scoped) public onlyOwner {
        allowedTargets[target].scoped = scoped;
        emit SetTargetScoped(target, allowedTargets[target].scoped);
    }

    /**
     * @notice Sets whether or not a target can be sent to (incluces fallback/receive functions).
     * @param target Address to be allow/disallow sends to.
     * @param allow Bool to allow (true) or disallow (false) sends on target.
     * @dev Only callable by owner.
     */
    function setFallbackAllowedOnTarget(
        address target,
        bool allow
    ) public onlyOwner {
        allowedTargets[target].fallbackAllowed = allow;
        emit SetFallbackAllowedOnTarget(
            target,
            allowedTargets[target].fallbackAllowed
        );
    }

    /**
     * @notice Sets whether or not a target can be sent to (incluces fallback/receive functions).
     * @param target Address to be allow/disallow sends to.
     * @param allow Bool to allow (true) or disallow (false) sends on target.
     * @dev Only callable by owner.
     */
    function setValueAllowedOnTarget(
        address target,
        bool allow
    ) public onlyOwner {
        allowedTargets[target].valueAllowed = allow;
        emit SetValueAllowedOnTarget(
            target,
            allowedTargets[target].valueAllowed
        );
    }

    /**
     * @notice Sets whether or not a specific function signature should be allowed on a scoped target.
     * @param target Scoped address on which a function signature should be allowed/disallowed.
     * @param functionSig Function signature to be allowed/disallowed.
     * @param allow Bool to allow (true) or disallow (false) calls a function signature on target.
     * @dev Only callable by owner.
     */
    function setAllowedFunction(
        address target,
        bytes4 functionSig,
        bool allow
    ) public onlyOwner {
        allowedTargets[target].allowedFunctions[functionSig] = allow;
        emit SetFunctionAllowedOnTarget(
            target,
            functionSig,
            allowedTargets[target].allowedFunctions[functionSig]
        );
    }
}
