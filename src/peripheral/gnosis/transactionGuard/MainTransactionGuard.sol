// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.12 <0.9.0;

import {BaseGuard, ITransactionGuard, IModuleGuard} from "safe-smart-account/examples/guards/BaseGuard.sol";
import {Enum} from "safe-smart-account/libraries/Enum.sol";
import {Owned} from "src/utils/Owned.sol";

contract MainTransactionGuard is BaseGuard, Owned {
    constructor(address owner_) Owned(owner_) {}

    // solhint-disable-next-line payable-fallback
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
     * @param safeTxGas Gas that should be used for the Safe transaction.
     * @param baseGas Gas costs that are independent of the transaction execution (e.g. base transaction fee, signature check, payment of the refund)
     * @param gasPrice Gas price that should be used for the payment calculation.
     * @param gasToken Token address (or 0 if ETH) that is used for the payment.
     * @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin).
     * @param signatures Signature data that should be verified. Can be packed ECDSA signature ({bytes32 r}{bytes32 s}{uint8 v}), contract signature (EIP-1271) or approved hash.
     * @param executor Account executing the transaction.
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        // solhint-disable-next-line no-unused-vars
        address payable refundReceiver,
        bytes memory signatures,
        address executor
    ) external override {
        address[] memory hooks = getHooks();

        for (uint256 i; i < hooks.length; i++) {
            ITransactionGuard(hooks[i]).checkTransaction(
                to,
                value,
                data,
                operation,
                safeTxGas,
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                signatures,
                executor
            );
        }
    }

    /**
     * @notice Called by the Safe contract after a transaction is executed.
     * @param txHash Hash of the executed transaction.
     * @param success True if the transaction was successful.
     */
    function checkAfterExecution(
        bytes32 txHash,
        bool success
    ) external override {
        address[] memory hooks = getHooks();

        for (uint256 i; i < hooks.length; i++) {
            ITransactionGuard(hooks[i]).checkAfterExecution(txHash, success);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        MODULE TRANSACTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks the module transaction details.
     * @dev The function needs to implement module transaction validation logic.
     * @param to The address to which the transaction is intended.
     * @param value The value of the transaction in Wei.
     * @param data The transaction data.
     * @param operation The type of operation of the module transaction.
     * @param module The module involved in the transaction.
     * @return moduleTxHash The hash of the module transaction.
     */
    function checkModuleTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        address module
    ) external returns (bytes32 moduleTxHash) {
        address[] memory hooks = getHooks();

        for (uint256 i; i < hooks.length; i++) {
            IModuleGuard(hooks[i]).checkModuleTransaction(
                to,
                value,
                data,
                operation,
                module
            );
        }
    }

    /**
     * @notice Checks after execution of module transaction.
     * @dev The function needs to implement a check after the execution of the module transaction.
     * @param txHash The hash of the module transaction.
     * @param success The status of the module transaction execution.
     */
    function checkAfterModuleExecution(bytes32 txHash, bool success) external {
        address[] memory hooks = getHooks();

        for (uint256 i; i < hooks.length; i++) {
            IModuleGuard(hooks[i]).checkAfterModuleExecution(txHash, success);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        HOOK LOGIC
    //////////////////////////////////////////////////////////////*/

    event AddedHook(address hook);
    event RemovedHook(address hook);

    address internal constant SENTINEL_HOOK = address(0x1);

    mapping(address => address) internal hooks;
    uint256 internal hookCount;

    /**
     * @notice Adds the hook `hook`
     * @dev This can only be done via a Safe transaction.
     * @param hook New hook address.
     */
    function addHook(address hook) public onlyOwner {
        // hook address cannot be null, the sentinel or the Safe itself.
        require(
            hook != address(0) &&
                hook != SENTINEL_HOOK &&
                hook != address(this),
            "GS203"
        );
        // No duplicate hooks allowed.
        require(hooks[hook] == address(0), "GS204");

        hooks[hook] = hooks[SENTINEL_HOOK];
        hooks[SENTINEL_HOOK] = hook;

        hookCount++;

        emit AddedHook(hook);
    }

    /**
     * @notice Replaces the hook `oldHook` in the Safe with `newHook`.
     * @dev This can only be done via a Safe transaction.
     * @param prevHook Owner that pointed to the owner to be replaced in the linked list
     * @param oldHook Owner address to be replaced.
     * @param newHook New owner address.
     */
    function swapHook(
        address prevHook,
        address oldHook,
        address newHook
    ) public onlyOwner {
        // Owner address cannot be null, the sentinel or the Safe itself.
        require(
            newHook != address(0) &&
                newHook != SENTINEL_HOOK &&
                newHook != address(this),
            "GS203"
        );
        // No duplicate owners allowed.
        require(hooks[newHook] == address(0), "GS204");
        // Validate oldOwner address and check that it corresponds to owner index.
        require(oldHook != address(0) && oldHook != SENTINEL_HOOK, "GS203");

        hooks[newHook] = hooks[oldHook];
        hooks[prevHook] = newHook;

        emit RemovedHook(oldHook);
        emit AddedHook(newHook);
    }

    /**
     * @notice Returns if `hook` is an owner of the Safe.
     * @return Boolean if hook is an owner of the Safe.
     */
    function isHook(address hook) public view returns (bool) {
        return hook != SENTINEL_HOOK && hooks[hook] != address(0);
    }

    /**
     * @notice Returns a list of Safe owners.
     * @return Array of Safe owners.
     */
    function getHooks() public view returns (address[] memory) {
        address[] memory array = new address[](hookCount);

        // populate return array
        uint256 index = 0;
        address currentHook = hooks[SENTINEL_HOOK];
        while (currentHook != SENTINEL_HOOK) {
            array[index] = currentHook;
            currentHook = hooks[currentHook];
            index++;
        }
        return array;
    }
}
