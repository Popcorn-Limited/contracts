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

    address public share = address(this);

    constructor(
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol
    ) Owned(_owner) ERC4626(ERC20(_asset), _name, _symbol) {}

    /*//////////////////////////////////////////////////////////////
                            ROLE LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 => mapping(address => bool)) public hasRole;

    event RoleUpdated(bytes32 role, address account, bool approved);

    function updateRole(
        bytes32 role,
        address account,
        bool approved
    ) public onlyOwner {
        hasRole[role][account] = approved;

        emit RoleUpdated(role, account, approved);
    }

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

    /// @notice Pause Deposits. Caller must be owner.
    function pause() external override onlyRoleOrOwner(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause Deposits. Caller must be owner.
    function unpause() external override onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(address => bool)) public isOperator;

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

    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual returns (bool) {
        return
            interfaceId == type(IERC7575).interfaceId ||
            interfaceId == type(IERC7540Operator).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
