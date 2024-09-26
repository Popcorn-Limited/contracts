// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20, IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "../../utils/OwnedUpgradeable.sol";
import {IERC7540Operator} from "ERC-7540/interfaces/IERC7540.sol";
import {IERC165} from "ERC-7540/interfaces/IERC7575.sol";

abstract contract AbstractBaseVault is
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnedUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    event VaultInitialized(bytes32 contractName, address indexed asset);

    event MultisigAdded(address indexed multisig, uint256 debtLimit);
    event MultisigRemoved(address indexed multisig);
    event MultisigDebtLimitUpdated(address indexed multisig, uint256 newLimit);
    event MultisigDebtChanged(address indexed multisig, uint256 newDebt);

    error InvalidAsset();
    error Duplicate();
    error NoMultisigs();
    error DebtLimitExceeded();
    error InvalidDebtLimit();
    error MultisigNotFound();
    error InsufficientMultisigBalance();

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     */
    function __BaseVault_init(
        IERC20 asset_,
        address owner_,
        address[] memory multisigAddresses,
        uint256[] memory debtLimits,
        uint256[] memory interestRates,
        uint256[] memory securityDeposits,
        uint256 depositLimit_
    ) internal initializer {
        __ERC4626_init(IERC20Metadata(address(asset_)));
        __Pausable_init();
        __ReentrancyGuard_init();
        __Owned_init(owner_);

        if (address(asset_) == address(0)) revert InvalidAsset();

        if (multisigAddresses.length == 0) revert();
        if (multisigAddresses.length != debtLimits.length) revert();

        depositLimit = depositLimit_;

        for (uint256 i = 0; i < multisigAddresses.length; i++) {
            addMultisig(
                multisigAddresses[i],
                debtLimits[i],
                interestRates[i],
                securityDeposits[i]
            );
        }

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
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    struct RedeemRequest {
        uint256 shares;
        uint256 requestTime;
    }

    struct ClaimableRedeem {
        uint256 assets;
        uint256 shares;
    }

    /// @dev Assume requests are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;

    mapping(address => mapping(address => RedeemRequest))
        public redeemRequests;
    mapping(address => uint256) internal _pendingRedeem;
    mapping(address => ClaimableRedeem) internal _claimableRedeem;

    mapping(address => mapping(address => bool)) public isOperator;
    mapping(address controller => mapping(bytes32 nonce => bool used))
        public authorizations;

    event RedeemRequested(
        address indexed recipient,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 shares,
        uint256 requestTime
    );

    event OperatorSet(
        address indexed controller,
        address indexed operator,
        bool approved
    ); 

    function _withdraw(
        uint256 assets,
        address controller
    ) internal returns (uint256 shares) {
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
        uint256 shareReduction = claimable.shares > sharesUp
            ? sharesUp
            : claimable.shares;

        claimable.assets -= assets;
        claimable.shares -= shareReduction;
    }

    function _redeem(
        uint256 shares,
        address controller
    ) internal returns (uint256 assets) {
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
        uint256 assetReduction = claimable.assets > assetsUp
            ? assetsUp
            : claimable.assets;

        claimable.assets -= assetReduction;
        claimable.shares -= shares;
    }

    /*//////////////////////////////////////////////////////////////
                            MULTISIG LOGIC
    //////////////////////////////////////////////////////////////*/

    struct DebtInfo {
        uint256 debtLimit;
        uint256 currentDebt;
        uint256 interestRate;
        uint256 securityDeposit;
    }

    address internal constant SENTINEL_MULTISIG = address(0x1);

    mapping(address => address) internal multisigs;
    mapping(address => DebtInfo) public debtInfo;
    uint256 internal multisigCount;

    event AddedMultisig(address multisig, uint256 debtLimit);
    event RemovedMultisig(address multisig);

    /**
     * @notice Adds the multisig `multisig` to the Safe and updates the threshold to `_threshold`.
     * @dev This can only be done via a Safe transaction.
     * @param multisig New multisig address.
     * @param debtLimit New threshold.
     */
    function addMultisig(
        address multisig,
        uint256 debtLimit,
        uint256 interestRate,
        uint256 securityDeposit
    ) public onlyOwner {
        // multisig address cannot be null, the sentinel or the Safe itself.
        require(
            multisig != address(0) &&
                multisig != SENTINEL_MULTISIG &&
                multisig != address(this),
            "GS203"
        );
        // No duplicate multisigs allowed.
        require(multisigs[multisig] == address(0), "GS204");

        multisigs[multisig] = multisigs[SENTINEL_MULTISIG];
        multisigs[SENTINEL_MULTISIG] = multisig;

        debtInfo[multisig] = DebtInfo({
            debtLimit: debtLimit,
            currentDebt: 0,
            interestRate: interestRate,
            securityDeposit: securityDeposit
        });

        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            msg.sender,
            address(this),
            securityDeposit
        );

        multisigCount++;

        emit AddedMultisig(multisig, debtLimit);
    }

    /**
     * @notice Removes the multisig `multisig` from the Safe and updates the threshold to `_threshold`.
     * @dev This can only be done via a Safe transaction.
     * @param prevMultisig Owner that pointed to the multisig to be removed in the linked list
     * @param multisig Owner address to be removed.
     */
    function removeMultisig(
        address prevMultisig,
        address multisig
    ) public onlyOwner {
        require(
            multisig != address(0) && multisig != SENTINEL_MULTISIG,
            "GS203"
        );
        require(multisigs[prevMultisig] == multisig, "GS205");
        require(debtInfo[multisig].currentDebt == 0, "GS205");

        // TODO - who do we sent it to?
        SafeERC20.safeTransfer(
            IERC20(asset()),
            multisig,
            debtInfo[multisig].securityDeposit
        );

        multisigs[prevMultisig] = multisigs[multisig];
        delete multisigs[multisig];
        delete debtInfo[multisig];
        multisigCount--;

        emit RemovedMultisig(multisig);
    }

    /**
     * @notice Replaces the multisig `oldOwner` in the Safe with `newOwner`.
     * @dev This can only be done via a Safe transaction.
     * @param prevMultisig Owner that pointed to the owner to be replaced in the linked list
     * @param oldMultisig Owner address to be replaced.
     * @param newMultisig New owner address.
     */
    function swapMultisig(
        address prevMultisig,
        address oldMultisig,
        address newMultisig,
        uint256 debtLimit,
        uint256 interestRate,
        uint256 securityDeposit
    ) public onlyOwner {
        // Owner address cannot be null, the sentinel or the Safe itself.
        require(
            newMultisig != address(0) &&
                newMultisig != SENTINEL_MULTISIG &&
                newMultisig != address(this),
            "GS203"
        );
        // No duplicate owners allowed.
        require(multisigs[newMultisig] == address(0), "GS204");
        // Validate oldOwner address and check that it corresponds to owner index.
        require(
            oldMultisig != address(0) && oldMultisig != SENTINEL_MULTISIG,
            "GS203"
        );
        require(multisigs[prevMultisig] == oldMultisig, "GS205");
        require(debtInfo[oldMultisig].currentDebt == 0, "GS205");

        // TODO - who do we sent it to?
        SafeERC20.safeTransfer(
            IERC20(asset()),
            oldMultisig,
            debtInfo[oldMultisig].securityDeposit
        );

        multisigs[newMultisig] = multisigs[oldMultisig];
        multisigs[prevMultisig] = newMultisig;
        delete multisigs[oldMultisig];
        delete debtInfo[oldMultisig];

        debtInfo[newMultisig] = DebtInfo({
            debtLimit: debtLimit,
            currentDebt: 0,
            interestRate: interestRate,
            securityDeposit: securityDeposit
        });

        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            msg.sender,
            address(this),
            securityDeposit
        );

        emit RemovedMultisig(oldMultisig);
        emit AddedMultisig(newMultisig, debtLimit);
    }

    /**
     * @notice Returns if `multisig` is an owner of the Safe.
     * @return Boolean if multisig is an owner of the Safe.
     */
    function isMultisig(address multisig) public view returns (bool) {
        return
            multisig != SENTINEL_MULTISIG && multisigs[multisig] != address(0);
    }

    /**
     * @notice Returns a list of Safe owners.
     * @return Array of Safe owners.
     */
    function getMultisigs() public view returns (address[] memory) {
        address[] memory array = new address[](multisigCount);

        // populate return array
        uint256 index = 0;
        address currentMultisig = multisigs[SENTINEL_MULTISIG];
        while (currentMultisig != SENTINEL_MULTISIG) {
            array[index] = currentMultisig;
            currentMultisig = multisigs[currentMultisig];
            index++;
        }
        return array;
    }

    function totalSecurityDeposit() public view returns (uint256) {
        uint256 securityDeposit;

        address currentMultisig = multisigs[SENTINEL_MULTISIG];
        while (currentMultisig != SENTINEL_MULTISIG) {
            securityDeposit += debtInfo[currentMultisig].securityDeposit;
            currentMultisig = multisigs[currentMultisig];
        }
        return securityDeposit;
    }

    function changeSecurityDeposit(
        address multisig,
        uint256 securityDeposit
    ) external onlyOwner {
        require(isMultisig(multisig), "not multisig");
        DebtInfo memory _debtInfo = debtInfo[multisig];

        // TODO -- whats the logic here?

        // TODO emit event
    }

    /*//////////////////////////////////////////////////////////////
                            DEBT LOGIC
    //////////////////////////////////////////////////////////////*/

    function changeDebtLimit(
        address multisig,
        uint256 debtLimit
    ) external onlyOwner {
        require(isMultisig(multisig), "not multisig");
        DebtInfo memory _debtInfo = debtInfo[multisig];

        if (_debtInfo.currentDebt < debtLimit) {
            _requestRedeem(
                _debtInfo.currentDebt - debtLimit,
                address(this),
                address(this),
                multisig
            );
        }

        _debtInfo.debtLimit = debtLimit;

        // TODO emit event
    }

    function requestRepayment(
        address multisig,
        uint256 shares
    ) external onlyOwner {
        _requestRedeem(shares, address(this), address(this), multisig);
    }

    function fullfillRepayment(uint256 shares) external {
        uint256 assets = convertToAssets(shares);
        _fullfillRequest(
            address(this),
            assets.mulDiv(
                10_000 - withdrawalIncentive,
                10_000,
                Math.Rounding.Floor
            ),
            shares
        );

        _claimableRedeem[address(this)].assets = 0;
        _claimableRedeem[address(this)].shares = 0;
    }

    function pullFunds(uint256 assets) external returns (uint256 shares) {
        require(isMultisig(msg.sender), "not multisig");
        DebtInfo memory _debtInfo = debtInfo[msg.sender];

        shares = convertToShares(assets);

        uint256 newDebt = _debtInfo.currentDebt + shares;
        require(newDebt <= _debtInfo.debtLimit, "respect debtLimit");

        debtInfo[msg.sender].currentDebt = newDebt;

        SafeERC20.safeTransfer(IERC20(asset()), msg.sender, assets);

        // TODO emit event
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL INCENTIVE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public withdrawalIncentive;

    event WithdrawalIncentiveChanged(uint256 previous, uint256 current);

    function setWithdrawalIncentive(
        uint256 withdrawalIncentive_
    ) external onlyOwner {
        // Dont take more than 10% withdrawalFee
        if (withdrawalIncentive_ > 1e17)
            revert InvalidFee(withdrawalIncentive_);

        emit WithdrawalIncentiveChanged(
            withdrawalIncentive,
            withdrawalIncentive_
        );

        withdrawalIncentive = withdrawalIncentive_;
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public performanceFee;
    uint256 public managementFee;

    uint256 public highWaterMark;
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
                          LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    uint256 public depositLimit;
    uint256 public minDeposit;
    uint256 public minWithdrawal;

    event DepositLimitSet(uint256 depositLimit);
    event MinValuesSet(
        uint256 oldMinDeposit,
        uint256 newMinDeposit,
        uint256 oldMinWithdrawal,
        uint256 newMinWithdrawal
    );

    /**
     * @notice Sets a limit for deposits in assets. Caller must be Owner.
     * @param depositLimit_ Maximum amount of assets that can be deposited.
     */
    function setDepositLimit(uint256 depositLimit_) external onlyOwner {
        depositLimit = depositLimit_;

        emit DepositLimitSet(depositLimit_);
    }

    function setMinValues(
        uint256 minDeposit_,
        uint256 minWithdrawal_
    ) external onlyOwner {
        // you should be able to withdraw the same as you deposit
        if (minWithdrawal_ < minDeposit_) revert();

        emit MinValuesSet(
            minDeposit,
            minDeposit_,
            minWithdrawal,
            minWithdrawal_
        );

        minDeposit = minDeposit_;
        minWithdrawal = minWithdrawal_;
    }

    /*//////////////////////////////////////////////////////////////
                            PAUSING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause Deposits. Caller must be owner.
    function pause() external virtual onlyOwner {
        _pause();
    }

    /// @notice Unpause Deposits. Caller must be owner.
    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            OPERATOR LOGIC
    //////////////////////////////////////////////////////////////*/

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
