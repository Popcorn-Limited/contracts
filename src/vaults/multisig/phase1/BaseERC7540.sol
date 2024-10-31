// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "src/utils/Owned.sol";
import {Pausable} from "src/utils/Pausable.sol";
import {IERC7540Operator} from "ERC-7540/interfaces/IERC7540.sol";
import {IERC7575} from "ERC-7540/interfaces/IERC7575.sol";
import {IERC165} from "ERC-7540/interfaces/IERC7575.sol";

abstract contract BaseERC7540 is
    ERC4626,
    Owned,
    ReentrancyGuard,
    Pausable,
    IERC7540Operator
{
    /// @dev Assume requests are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;

    /// @dev Required for IERC7575
    address public share = address(this);

    /**
     * @notice Constructor for BaseERC7540
     * @param _owner The permissioned owner of the vault (controls all management functions)
     * @param _asset The address of the underlying asset
     * @param _name The name of the vault
     * @param _symbol The symbol of the vault
     */
    constructor(
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol
    ) Owned(_owner) ERC4626(ERC20(_asset), _name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                            ROLE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev role => account => approved
    mapping(bytes32 => mapping(address => bool)) public hasRole;

    event RoleUpdated(bytes32 role, address account, bool approved);

    /**
     * @notice Update the role for an account
     * @param role The role to update
     * @param account The account to update
     * @param approved The approval status to set
     */
    function updateRole(
        bytes32 role,
        address account,
        bool approved
    ) public onlyOwner {
        hasRole[role][account] = approved;

        emit RoleUpdated(role, account, approved);
    }

    /**
     * @notice Modifier to check if the caller has the specified role or is the owner
     * @param role The role to check
     */
    modifier onlyRoleOrOwner(bytes32 role) {
        require(
            hasRole[role][msg.sender] || msg.sender == owner,
            "BaseERC7540/not-authorized"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Pause Deposits. Caller must be owner or have the PAUSER_ROLE
    function pause() external override onlyRoleOrOwner(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause Deposits. Caller must be owner
    function unpause() external override onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev controller => operator => approved
    mapping(address => mapping(address => bool)) public isOperator;

    /**
     * @notice Set the approval status for an operator
     * @param operator The operator to set
     * @param approved The approval status to set
     * @dev Operators are approved to requestRedeem,withdraw and redeem for the msg.sender using the balance of msg.sender
     */
    function setOperator(
        address operator,
        bool approved
    ) public virtual returns (bool success) {
        require(
            msg.sender != operator,
            "ERC7540Vault/cannot-set-self-as-operator"
        );
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        success = true;
    }

    /*//////////////////////////////////////////////////////////////
                        EIP-7441 LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(address controller => mapping(bytes32 nonce => bool used))
        public authorizations;

    /**
     * @notice Authorize an operator for a controller
     * @param controller The controller to authorize the operator for
     * @param operator The operator to authorize
     * @param approved The approval status to set
     * @param nonce The nonce to use for the authorization
     * @param deadline The deadline for the authorization
     * @param signature The signature to verify the authorization
     * @dev Operators are approved to requestRedeem,withdraw and redeem for the msg.sender using the balance of msg.sender
     */
    function authorizeOperator(
        address controller,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    ) public virtual returns (bool success) {
        require(
            controller != operator,
            "ERC7540Vault/cannot-set-self-as-operator"
        );
        require(block.timestamp <= deadline, "ERC7540Vault/expired");
        require(
            !authorizations[controller][nonce],
            "ERC7540Vault/authorization-used"
        );

        authorizations[controller][nonce] = true;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            keccak256(
                                "AuthorizeOperator(address controller,address operator,bool approved,bytes32 nonce,uint256 deadline)"
                            ),
                            controller,
                            operator,
                            approved,
                            nonce,
                            deadline
                        )
                    )
                )
            ),
            v,
            r,
            s
        );

        require(
            recoveredAddress != address(0) && recoveredAddress == controller,
            "INVALID_SIGNER"
        );

        isOperator[controller][operator] = approved;

        emit OperatorSet(controller, operator, approved);

        success = true;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if the contract supports an interface
     * @param interfaceId The interface ID to check
     * @return True if the contract supports the interface, false otherwise
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual returns (bool) {
        return
            interfaceId == type(IERC7575).interfaceId ||
            interfaceId == type(IERC7540Operator).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
