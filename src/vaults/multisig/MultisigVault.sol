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
// import {AbstractVaultSettings} from "./AbstractVaultSettings.sol";
import {AbstractBaseVault} from "./AbstractBaseVault.sol";

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
contract MultisigVault is AbstractBaseVault {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IOracle public oracle;
    uint256 public quitPeriod;

    // constructor() {
    //     _disableInitializers();
    // }

    /**
     * @notice Initialize a new Vault.
     * @param asset_ Underlying Asset which users will deposit.
     * @param multisigAddresses_ Multisig addresses
     * @param debtLimits_ Debt limits for each multisig
     * @param oracle_ Oracle
     * @param depositLimit_ Maximum amount of assets which can be deposited.
     * @param owner_ Owner of the contract. Controls management functions.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev Usually the adapter should already be pre configured. Otherwise a new one can only be added after a ragequit time.
     * @dev overflows if depositLimit is close to maxUint (convertToShares multiplies depositLimit with totalSupply)
     */
    function initialize(
        IERC20 asset_,
        address[] memory multisigAddresses_,
        uint256[] memory debtLimits_,
        uint256[] memory interestRates_,
        uint256[] memory securityDeposits_,
        address oracle_,
        uint256 depositLimit_,
        address owner_
    ) external initializer {
        __BaseVault_init(
            asset_,
            owner_,
            multisigAddresses_,
            debtLimits_,
            interestRates_,
            securityDeposits_,
            depositLimit_
        );

        oracle = IOracle(oracle_);
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
        pendingShares = _pendingRedeem[controller];
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
        // TODO write revert message
        if (shares < minDeposit) revert();

        // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

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

        if (!paused()) {
            shares = _withdraw(assets, controller);
        }

        _takeFees();

        _burn(address(this), shares);

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

        if (paused()) {
            ClaimableRedeem storage claimable = _claimableRedeem[controller];
        } else {
            assets = _redeem(shares, controller);
        }

        _takeFees();

        _burn(address(this), shares);

        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }
}
