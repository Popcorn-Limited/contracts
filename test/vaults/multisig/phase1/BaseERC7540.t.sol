// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {BaseERC7540} from "src/vaults/multisig/phase1/BaseERC7540.sol";

contract MockERC7540 is BaseERC7540 {
    constructor(
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol
    ) BaseERC7540(_owner, _asset, _name, _symbol) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract BaseERC7540Test is Test {
    MockERC7540 vault;
    MockERC20 asset;
    
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);

    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    event RoleUpdated(bytes32 role, address account, bool approved);
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");

        asset = new MockERC20("Test Token", "TEST", 18);
        vault = new MockERC7540(owner, address(asset), "Vault Token", "vTEST");
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateRole() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit RoleUpdated(PAUSER_ROLE, alice, true);
        vault.updateRole(PAUSER_ROLE, alice, true);
        
        assertTrue(vault.hasRole(PAUSER_ROLE, alice));
        
        vm.expectEmit(true, true, true, true);
        emit RoleUpdated(PAUSER_ROLE, alice, false);
        vault.updateRole(PAUSER_ROLE, alice, false);
        
        assertFalse(vault.hasRole(PAUSER_ROLE, alice));
        vm.stopPrank();
    }

    function testUpdateRoleNonOwner() public {
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        vault.updateRole(PAUSER_ROLE, bob, true);
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function testPause() public {
        // Grant PAUSER_ROLE to alice
        vm.prank(owner);
        vault.updateRole(PAUSER_ROLE, alice, true);

        // Test pause as role holder
        vm.prank(alice);
        vault.pause();
        assertTrue(vault.paused());

        // Test pause as owner
        vm.prank(owner);
        vault.unpause();
        assertFalse(vault.paused());
        vault.pause();
        assertTrue(vault.paused());
    }

    function testPauseUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert("BaseERC7540/not-authorized");
        vault.pause();
    }

    function testUnpauseOnlyOwner() public {
        // First pause
        vm.prank(owner);
        vault.pause();
        
        // Try to unpause as non-owner
        vm.prank(alice);
        vm.expectRevert("UNAUTHORIZED");
        vault.unpause();

        // Unpause as owner
        vm.prank(owner);
        vault.unpause();
        assertFalse(vault.paused());
    }

    /*//////////////////////////////////////////////////////////////
                        OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetOperator() public {
        vm.startPrank(alice);
        
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(alice, bob, true);
        assertTrue(vault.setOperator(bob, true));
        assertTrue(vault.isOperator(alice, bob));
        
        vm.expectEmit(true, true, true, true);
        emit OperatorSet(alice, bob, false);
        assertTrue(vault.setOperator(bob, false));
        assertFalse(vault.isOperator(alice, bob));
        
        vm.stopPrank();
    }

    function testCannotSetSelfAsOperator() public {
        vm.prank(alice);
        vm.expectRevert("ERC7540Vault/cannot-set-self-as-operator");
        vault.setOperator(alice, true);
    }

    /*//////////////////////////////////////////////////////////////
                    AUTHORIZE OPERATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function testAuthorizeOperator() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 deadline = block.timestamp + 1 hours;
        
        bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                alice,
                bob,
                true,
                nonce,
                deadline
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash); // alice's private key
        bytes memory signature = abi.encodePacked(r, s, v);

        assertTrue(
            vault.authorizeOperator(
                alice,
                bob,
                true,
                nonce,
                deadline,
                signature
            )
        );
        assertTrue(vault.isOperator(alice, bob));
    }

    function testAuthorizeOperatorExpired() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 deadline = block.timestamp - 1;
        
        vm.expectRevert("ERC7540Vault/expired");
        vault.authorizeOperator(
            alice,
            bob,
            true,
            nonce,
            deadline,
            new bytes(65)
        );
    }

    function testAuthorizeOperatorUsedNonce() public {
        bytes32 nonce = bytes32(uint256(1));
        uint256 deadline = block.timestamp + 1 hours;
        
        // First use
        bytes32 domainSeparator = vault.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                ),
                alice,
                bob,
                true,
                nonce,
                deadline
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vault.authorizeOperator(
            alice,
            bob,
            true,
            nonce,
            deadline,
            signature
        );

        // Try to use same nonce again
        vm.expectRevert("ERC7540Vault/authorization-used");
        vault.authorizeOperator(
            alice,
            bob,
            true,
            nonce,
            deadline,
            signature
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ERC165 TESTS
    //////////////////////////////////////////////////////////////*/

    function testSupportsInterface() public {
        assertTrue(vault.supportsInterface(type(IERC7575).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC7540Operator).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC165).interfaceId));
        assertFalse(vault.supportsInterface(bytes4(0xdeadbeef)));
    }
}