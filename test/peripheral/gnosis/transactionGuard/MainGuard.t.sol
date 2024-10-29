// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MainTransactionGuard} from "src/peripheral/gnosis/transactionGuard/MainTransactionGuard.sol";
import {IGnosisSafe} from "src/interfaces/external/IGnosisSafe.sol";

contract MainGuardTest is Test {
    // Constants
    address constant SAFE = 0x3C99dEa58119DE3962253aea656e61E5fBE21613;
    address constant SAFE_OWNER = 0x9E1028F5F1D5eDE59748FFceE5532509976840E0; // Replace with actual owner
    uint256 constant FORK_BLOCK = 164793616; // Replace with appropriate block

    // Contracts
    IGnosisSafe safe;
    MainTransactionGuard guard;

    function setUp() public {
        // Fork arbitrum at specific block
        vm.createSelectFork("arbitrum", FORK_BLOCK);

        // Label addresses for better trace output
        vm.label(SAFE, "Gnosis Safe");
        vm.label(SAFE_OWNER, "Safe Owner");

        // Get Safe contract instance
        safe = IGnosisSafe(SAFE);

        // Deploy guard
        guard = new MainTransactionGuard(SAFE_OWNER);
        vm.label(address(guard), "Transaction Guard");
    }

    function testSetGuard() public {
        // Prepare setGuard transaction data
        bytes memory data = abi.encodeWithSignature(
            "setGuard(address)",
            address(guard)
        );

        // Get current nonce
        uint256 nonce = safe.nonce();

        // Calculate transaction hash
        bytes32 txHash = safe.getTransactionHash(
            address(safe), // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            address(0), // refundReceiver
            nonce // nonce
        );

        // Get signature from owner (assuming single owner for simplicity)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked(SAFE_OWNER))), // Owner's private key
            txHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execute transaction
        vm.prank(SAFE_OWNER);
        safe.execTransaction(
            address(safe), // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signature // signatures
        );

        // Verify guard was set
        assertEq(safe.getGuard(), address(guard));
    }

    function testGuardFunctionality() public {
        // First set the guard
        testSetGuard();

        // Test a basic transaction through the guard
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(0x123), // random recipient
            1 ether
        );

        uint256 nonce = safe.nonce();

        bytes32 txHash = safe.getTransactionHash(
            address(0x123), // to
            0, // value
            transferData, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            address(0), // refundReceiver
            nonce // nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked(SAFE_OWNER))),
            txHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Execute transaction through guard
        vm.prank(SAFE_OWNER);
        safe.execTransaction(
            address(0x123), // to
            0, // value
            transferData, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signature // signatures
        );
    }

    function testAddHook() public {
        // First set the guard
        testSetGuard();

        // Deploy a mock hook
        address mockHook = address(0x123);

        // Prepare addHook transaction data
        bytes memory data = abi.encodeWithSignature(
            "addHook(address)",
            mockHook
        );

        uint256 nonce = safe.nonce();

        bytes32 txHash = safe.getTransactionHash(
            address(guard), // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            address(0), // refundReceiver
            nonce // nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked(SAFE_OWNER))),
            txHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Add hook through safe transaction
        vm.prank(SAFE_OWNER);
        safe.execTransaction(
            address(guard), // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signature // signatures
        );

        // Verify hook was added
        assertTrue(guard.isHook(mockHook));
    }

    function testRemoveHook() public {
        // First add a hook
        testAddHook();

        address mockHook = address(0x123);

        // Find previous hook in linked list
        address prevHook = address(0x1); // SENTINEL_HOOK
        address[] memory hooks = guard.getHooks();
        for (uint256 i = 0; i < hooks.length; i++) {
            if (hooks[i] == mockHook) {
                break;
            }
            prevHook = hooks[i];
        }

        // Prepare swapHook transaction data (removing by swapping with 0 address)
        bytes memory data = abi.encodeWithSignature(
            "swapHook(address,address,address)",
            prevHook,
            mockHook,
            address(0)
        );

        uint256 nonce = safe.nonce();

        bytes32 txHash = safe.getTransactionHash(
            address(guard), // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            address(0), // refundReceiver
            nonce // nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256(abi.encodePacked(SAFE_OWNER))),
            txHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Remove hook through safe transaction
        vm.prank(SAFE_OWNER);
        safe.execTransaction(
            address(guard), // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            signature // signatures
        );

        // Verify hook was removed
        assertFalse(guard.isHook(mockHook));
    }
}
