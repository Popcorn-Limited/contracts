// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20, IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnedUpgradeable} from "../../utils/OwnedUpgradeable.sol";

abstract contract AbstractVaultStorage {
    // GENERAL STORAGE
    string internal _name;
    string internal _symbol;
    bytes32 public contractName;
    uint256 internal constant REQUEST_ID = 0;
    address internal constant SENTINEL_MULTISIG = address(0x1);
    address public constant FEE_RECIPIENT =
        address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    // ERC7540 STORAGE
    struct RedeemRequest {
        uint256 shares;
        uint256 requestTime;
    }

    struct ClaimableRedeem {
        uint256 assets;
        uint256 shares;
    }

    mapping(address => mapping(address => RedeemRequest))
        internal _redeemRequests;
    mapping(address => uint256) internal _pendingRedeem;
    mapping(address => ClaimableRedeem) internal _claimableRedeem;

    event RedeemRequested(
        address indexed recipient,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 shares,
        uint256 requestTime
    );

    // OPERATOR STORAGE
    mapping(address => mapping(address => bool)) public isOperator;
    mapping(address controller => mapping(bytes32 nonce => bool used))
        public authorizations;

    event OperatorSet(
        address indexed controller,
        address indexed operator,
        bool approved
    );

    // MULTISIG STORAGE
    struct DebtInfo {
        uint256 debtLimit;
        uint256 currentDebt;
        address oracle;
        uint256 hwm;
        uint256 hwmAfterFee;
        uint256 lastUpdate;
    }

    mapping(address => address) internal multisigs;
    mapping(address => DebtInfo) public debtInfo;
    uint256 internal multisigCount;

    event MultisigAdded(address indexed multisig, uint256 debtLimit);
    event MultisigRemoved(address indexed multisig);
    event MultisigDebtLimitUpdated(address indexed multisig, uint256 newLimit);
    event MultisigDebtChanged(address indexed multisig, uint256 newDebt);
    event AddedMultisig(address multisig, uint256 debtLimit);
    event RemovedMultisig(address multisig);

    error NoMultisigs();
    error DebtLimitExceeded();
    error InvalidDebtLimit();
    error MultisigNotFound();
    error InsufficientMultisigBalance();

    // FEE STORAGE
    uint256 public fullfillmentIncentive;
    uint256 public performanceFee;
    uint256 public managementFee;
    uint256 public highWaterMark;
    uint256 public feesUpdatedAt;

    event UpdatedFullfillmentIncentive(uint256 previous, uint256 current);
    event UpdatedFees(
        uint256 oldPerformanceFee,
        uint256 newPerformanceFee,
        uint256 oldManagementFee,
        uint256 newManagementFee
    );

    error InvalidFee(uint256 fee);

    // LIMIT STORAGE
    uint256 public depositLimit;
    uint256 public minAmount;

    event UpdatedLimits(
        uint256 oldDepositLimit,
        uint256 newDepositLimit,
        uint256 oldMinAmount,
        uint256 newMinAmount
    );

    // EIP-2612 STORAGE
    uint256 internal INITIAL_CHAIN_ID;
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    error PermitDeadlineExpired(uint256 deadline);
    error InvalidSigner(address signer);
}
