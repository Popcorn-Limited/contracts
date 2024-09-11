// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20, IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../utils/OwnedUpgradeable.sol";
import {IERC7540Operator} from "ERC-7540/interfaces/IERC7540.sol";
import {IERC165} from "ERC-7540/interfaces/IERC7575.sol";

struct PendingRedeem {
    uint256 shares;
}

struct ClaimableRedeem {
    uint256 assets;
    uint256 shares;
}

interface IOracle {
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view returns (uint256 outAmount);
}

/**
 * @title   MultiStrategyVault
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * A simple ERC4626-Implementation of a MultiStrategyVault.
 * The vault delegates any actual protocol interaction to a selection of strategies.
 * It allows for multiple type of fees which are taken by issuing new vault shares.
 * Strategies and fees can be changed by the owner after a ragequit time.
 */
contract MultisigVault is
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnedUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    IOracle public oracle;
    address public multisig;
    uint256 public quitPeriod;

    /// @dev Assume requests are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;

    mapping(address => mapping(address => bool)) public isOperator;
    mapping(address controller => mapping(bytes32 nonce => bool used))
        public authorizations;

    mapping(address => PendingRedeem) internal _pendingRedeem;
    mapping(address => ClaimableRedeem) internal _claimableRedeem;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    error InvalidAsset();
    error Duplicate();

    // constructor() {
    //     _disableInitializers();
    // }

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     * @param multisig_ Multisig
     * @param oracle_ Oracle
     * @param depositLimit_ Maximum amount of assets which can be deposited.
     * @param owner_ Owner of the contract. Controls management functions.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     * @dev overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
     */
    function initialize(
        IERC20 asset_,
        address multisig_,
        address oracle_,
        uint256 depositLimit_,
        address owner_
    ) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Owned_init(owner_);

        if (address(asset_) == address(0)) revert InvalidAsset();

        multisig = multisig_;
        oracle = IOracle(oracle_);

        // Set other state variables
        quitPeriod = 3 days;
        depositLimit = depositLimit_;
        highWaterMark = convertToAssets(1e18);

        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(address(asset_)).name(),
            " Vault"
        );
        _symbol = string.concat(
            "vc-",
            IERC20Metadata(address(asset_)).symbol()
        );

        contractName = keccak256(
            abi.encodePacked("VaultCraft ", name(), block.timestamp, "Vault")
        );

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();

        emit VaultInitialized(contractName, address(asset_));
    }

    function name()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _name;
    }

    function symbol()
        public
        view
        override(IERC20Metadata, ERC20)
        returns (string memory)
    {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error Misconfigured();

    function deposit(uint256 assets) external returns (uint256) {
        return deposit(assets, msg.sender);
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    function withdraw(uint256 assets) external returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override nonReentrant {
        if (shares == 0 || assets == 0) revert ZeroAmount();

        // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, multisig, assets);

        _mint(receiver, shares);

        _takeFees();

        emit Deposit(caller, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override returns (uint256 shares) {
        require(
            controller == msg.sender || isOperator[controller][msg.sender],
            "ERC7540Vault/invalid-caller"
        );
        require(assets != 0, "Must claim nonzero amount");

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        ClaimableRedeem storage claimable = _claimableRedeem[controller];
        shares = assets.mulDiv(
            claimable.shares,
            claimable.assets,
            Math.Rounding.Floor
        );
        uint256 sharesUp = assets.mulDiv(
            claimable.shares,
            claimable.assets,
            Math.Rounding.Ceil
        );

        claimable.assets -= assets;
        claimable.shares = claimable.shares > sharesUp
            ? claimable.shares - sharesUp
            : 0;

        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override returns (uint256 assets) {
        require(
            controller == msg.sender || isOperator[controller][msg.sender],
            "ERC7540Vault/invalid-caller"
        );
        require(shares != 0, "Must claim nonzero amount");

        // Claiming partially introduces precision loss. The user therefore receives a rounded down amount,
        // while the claimable balance is reduced by a rounded up amount.
        ClaimableRedeem storage claimable = _claimableRedeem[controller];
        assets = shares.mulDiv(
            claimable.assets,
            claimable.shares,
            Math.Rounding.Floor
        );
        uint256 assetsUp = shares.mulDiv(
            claimable.assets,
            claimable.shares,
            Math.Rounding.Ceil
        );

        claimable.assets = claimable.assets > assetsUp
            ? claimable.assets - assetsUp
            : 0;
        claimable.shares -= shares;

        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        return oracle.getQuote(totalSupply(), address(this), asset());
    }

    // Preview functions always revert for async flows
    function previewWithdraw(
        uint256
    ) public pure virtual override returns (uint256) {
        revert("ERC7540Vault/async-flow");
    }

    function previewRedeem(
        uint256
    ) public pure virtual override returns (uint256) {
        revert("ERC7540Vault/async-flow");
    }

    function pendingRedeemRequest(
        uint256,
        address controller
    ) public view returns (uint256 pendingShares) {
        pendingShares = _pendingRedeem[controller].shares;
    }

    function claimableRedeemRequest(
        uint256,
        address controller
    ) public view returns (uint256 claimableShares) {
        claimableShares = _claimableRedeem[controller].shares;
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Maximum amount of underlying `asset` token that may be deposited for a given address.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        return
            (paused() || assets >= depositLimit_) ? 0 : depositLimit_ - assets;
    }

    /// @return Maximum amount of vault shares that may be minted to given address.
    /// @dev overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
    function maxMint(address) public view override returns (uint256) {
        uint256 assets = totalAssets();
        uint256 depositLimit_ = depositLimit;
        if (paused() || assets >= depositLimit_) return 0;

        if (depositLimit_ == type(uint256).max) return depositLimit_;

        return convertToShares(depositLimit_ - assets);
    }

    function maxWithdraw(
        address controller
    ) public view virtual override returns (uint256) {
        return _claimableRedeem[controller].assets;
    }

    function maxRedeem(
        address controller
    ) public view virtual override returns (uint256) {
        return _claimableRedeem[controller].shares;
    }

    /*//////////////////////////////////////////////////////////////
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    event RedeemRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 assets
    );
    event OperatorSet(
        address indexed controller,
        address indexed operator,
        bool approved
    );

    /// @notice this deposit request is added to any pending deposit request
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external returns (uint256 requestId) {
        require(
            owner == msg.sender || isOperator[owner][msg.sender],
            "ERC7540Vault/invalid-owner"
        );
        require(
            ERC20(address(this)).balanceOf(owner) >= shares,
            "ERC7540Vault/insufficient-balance"
        );
        require(shares != 0, "ZERO_SHARES");

        SafeERC20.safeTransferFrom(this, owner, address(this), shares);

        uint256 currentPendingShares = _pendingRedeem[controller].shares;
        _pendingRedeem[controller] = PendingRedeem(
            shares + currentPendingShares
        );

        emit RedeemRequest(controller, owner, REQUEST_ID, msg.sender, shares);
        return REQUEST_ID;
    }

    function fulfillRedeem(
        address controller,
        uint256 shares
    ) public onlyOwner returns (uint256 assets) {
        PendingRedeem storage request = _pendingRedeem[controller];
        require(request.shares != 0 && shares <= request.shares, "ZERO_SHARES");

        assets = convertToAssets(shares);

        _claimableRedeem[controller] = ClaimableRedeem(
            _claimableRedeem[controller].assets + assets,
            _claimableRedeem[controller].shares + shares
        );

        request.shares -= shares;
    }

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
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;
    uint256 public highWaterMark;

    uint256 public managementFee;
    uint256 public feesUpdatedAt;

    address public constant FEE_RECIPIENT =
        address(0x47fd36ABcEeb9954ae9eA1581295Ce9A8308655E);
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    event FeesChanged(
        uint256 oldPerformanceFee,
        uint256 newPerformanceFee,
        uint256 oldManagementFee,
        uint256 newManagementFee
    );

    error InvalidFee(uint256 fee);

    /**
     * @notice Performance fee that has accrued since last fee harvest.
     * @return Accrued performance fee in underlying `asset` token.
     * @dev Performance fee is based on a high water mark value. If vault share value has increased above the
     *   HWM in a fee period, issue fee shares to the vault equal to the performance fee.
     */
    function accruedPerformanceFee() public view returns (uint256) {
        uint256 highWaterMark_ = highWaterMark;
        uint256 shareValue = convertToAssets(1e18);
        uint256 performanceFee_ = performanceFee;

        return
            performanceFee_ > 0 && shareValue > highWaterMark_
                ? performanceFee_.mulDiv(
                    (shareValue - highWaterMark_) * totalSupply(),
                    1e36,
                    Math.Rounding.Ceil
                )
                : 0;
    }

    /**
     * @notice Management fee that has accrued since last fee harvest.
     * @return Accrued management fee in underlying `asset` token.
     * @dev Management fee is annualized per minute, based on 525,600 minutes per year. Total assets are calculated using
     *  the average of their current value and the value at the previous fee harvest checkpoint. This method is similar to
     *  calculating a definite integral using the trapezoid rule.
     */
    function accruedManagementFee() public view returns (uint256) {
        uint256 managementFee_ = managementFee;

        return
            managementFee_ > 0
                ? managementFee_.mulDiv(
                    totalAssets() * (block.timestamp - feesUpdatedAt),
                    SECONDS_PER_YEAR,
                    Math.Rounding.Floor
                ) / 1e18
                : 0;
    }

    /**
     * @notice Set a new performance fee for this adapter. Caller must be owner.
     * @param performanceFee_ performance fee in 1e18.
     * @param managementFee_ management fee in 1e18.
     * @dev Performance fee can be 0 but never more than 2e17 (1e18 = 100%, 1e14 = 1 BPS)
     * @dev Management fee can be 0 but never more than 1e17 (1e18 = 100%, 1e14 = 1 BPS)
     */
    function setFees(
        uint256 performanceFee_,
        uint256 managementFee_
    ) public onlyOwner {
        // Dont take more than 20% performanceFee
        if (performanceFee_ > 2e17) revert InvalidFee(performanceFee_);
        // Dont take more than 10% managementFee
        if (managementFee_ > 1e17) revert InvalidFee(managementFee_);

        _takeFees();

        emit FeesChanged(
            performanceFee,
            performanceFee_,
            managementFee,
            managementFee_
        );

        performanceFee = performanceFee_;
        managementFee = managementFee_;
    }

    function takeFees() external {
        _takeFees();
    }

    function _takeFees() internal {
        uint256 fee = accruedPerformanceFee() + accruedManagementFee();
        uint256 shareValue = convertToAssets(1e18);

        if (shareValue > highWaterMark) highWaterMark = shareValue;

        if (fee > 0) _mint(FEE_RECIPIENT, convertToShares(fee));

        feesUpdatedAt = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public depositLimit;

    event DepositLimitSet(uint256 depositLimit);

    /**
     * @notice Sets a limit for deposits in assets. Caller must be Owner.
     * @param _depositLimit Maximum amount of assets that can be deposited.
     */
    function setDepositLimit(uint256 _depositLimit) external onlyOwner {
        depositLimit = _depositLimit;

        emit DepositLimitSet(_depositLimit);
    }

    /*//////////////////////////////////////////////////////////////
                          PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause deposits. Caller must be Owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause deposits. Caller must be Owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    //  EIP-2612 STORAGE
    uint256 internal INITIAL_CHAIN_ID;
    bytes32 internal INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    error PermitDeadlineExpired(uint256 deadline);
    error InvalidSigner(address signer);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (deadline < block.timestamp) revert PermitDeadlineExpired(deadline);

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0) || recoveredAddress != owner) {
                revert InvalidSigner(recoveredAddress);
            }

            _approve(recoveredAddress, spender, value);
        }
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(name())),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure virtual returns (bool) {
        return
            interfaceId == type(IERC4626).interfaceId ||
            interfaceId == type(IERC7540Operator).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
