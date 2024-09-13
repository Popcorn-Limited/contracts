// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {ERC4626Upgradeable, IERC20Metadata, ERC20Upgradeable as ERC20, IERC4626, IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OwnedUpgradeable} from "src/utils/OwnedUpgradeable.sol";
import {AbstractBaseVault} from "./AbstractBaseVault.sol";

/**
 * @title   BaseStrategy
 * @author  RedVeil
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 *
 * The ERC4626 compliant base contract for all adapter contracts.
 * It allows interacting with an underlying protocol.
 * All specific interactions for the underlying protocol need to be overriden in the actual implementation.
 * The adapter can be initialized with a strategy that can perform additional operations. (Leverage, Compounding, etc.)
 */
abstract contract AbstractVaultSettings is
    PausableUpgradeable,
    OwnedUpgradeable,
    ReentrancyGuardUpgradeable,
    AbstractBaseVault
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @notice Initialize a new Strategy.
     * @param asset_ Underlying Asset which users will deposit.
     * @param owner_ Owner of the contract. Controls management functions.
     */
    function __VaultSettings_init(
        IERC20 asset_,
        address owner_
    ) internal onlyInitializing {
        __Pausable_init();
        __ReentrancyGuard_init();
        __Owned_init(owner_);
        __BaseVault_init(asset_);
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER LOGIC
    //////////////////////////////////////////////////////////////*/

    address public keeper;

    event KeeperChanged(address prev, address curr);

    error NotKeeperNorOwner();

    function setKeeper(address keeper_) external onlyOwner {
        emit KeeperChanged(keeper, keeper_);
        keeper = keeper_;
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && msg.sender != keeper) {
            revert NotKeeperNorOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            KEEPER LOGIC
    //////////////////////////////////////////////////////////////*/

    address public keeper;

    event KeeperChanged(address prev, address curr);

    error NotKeeperNorOwner();

    function setKeeper(address keeper_) external onlyOwner {
        emit KeeperChanged(keeper, keeper_);
        keeper = keeper_;
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != owner && msg.sender != keeper) {
            revert NotKeeperNorOwner();
        }
        _;
    }

    

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
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
            withdrawlIncentive,
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
     * @param _depositLimit Maximum amount of assets that can be deposited.
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
}
