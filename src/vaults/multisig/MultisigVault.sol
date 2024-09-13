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
import {AbstractVaultSettings} from "./AbstractVaultSettings.sol";

struct PendingRedeem {
    uint256 shares;
    uint256 requestTime;
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
contract MultisigVault is AbstractVaultSettings {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    bytes32 public contractName;

    IOracle public oracle;
    address public multisig;
    uint256 public quitPeriod;

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
        __VaultSettings_init(asset_, owner_);

        if (address(asset_) == address(0)) revert InvalidAsset();

        multisig = multisig_;
        oracle = IOracle(oracle_);

        emit VaultInitialized(contractName, address(asset_));
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
                        ERC7540 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Assume requests are non-fungible and all have ID = 0
    uint256 internal constant REQUEST_ID = 0;

    mapping(address => mapping(address => bool)) public isOperator;
    mapping(address controller => mapping(bytes32 nonce => bool used))
        public authorizations;

    mapping(address => PendingRedeem) internal _pendingRedeem;
    mapping(address => ClaimableRedeem) internal _claimableRedeem;

    event RedeemRequest(
        address indexed controller,
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
        require(shares != 0, "ZERO_SHARES");

        SafeERC20.safeTransferFrom(this, owner, address(this), shares);

        // When paused all assets are transfered from multisig to the vault
        if (!paused()) {
            _pendingRedeem[controller] = PendingRedeem({
                shares: shares + _pendingRedeem[controller].shares,
                requestTime: block.timestamp
            });
        }

        emit RedeemRequest(
            controller,
            owner,
            REQUEST_ID,
            msg.sender,
            shares,
            block.timestamp
        );
        return REQUEST_ID;
    }

    function fulfillRedeem(
        address controller,
        uint256 shares
    ) public onlyOwner whenNotPaused returns (uint256 assets) {
        PendingRedeem storage request = _pendingRedeem[controller];
        require(request.shares != 0 && shares <= request.shares, "ZERO_SHARES");

        assets = convertToAssets(shares);

        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            multisig,
            address(this),
            assets
        );

        _claimableRedeem[controller] = ClaimableRedeem(
            _claimableRedeem[controller].assets + assets,
            _claimableRedeem[controller].shares + shares
        );

        request.shares -= shares;

        _takeFees();
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
}
