// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.25;

import "./AbstractBaseVaultStorage.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

abstract contract AbstractBaseVault is AbstractBaseVaultStorage {
    using SafeERC20 for IERC20;
    using Math for uint256;

    event VaultInitialized(bytes32 contractName, address indexed asset);
    event MultisigAdded(address indexed multisig, uint256 debtLimit);
    event MultisigRemoved(address indexed multisig);
    event MultisigDebtLimitUpdated(address indexed multisig, uint256 newLimit);
    event MultisigDebtChanged(address indexed multisig, uint256 newDebt);
    event WithdrawalIncentiveChanged(uint256 previous, uint256 current);
    event FeesChanged(
        uint256 oldPerformanceFee,
        uint256 newPerformanceFee,
        uint256 oldManagementFee,
        uint256 newManagementFee
    );
    event DepositLimitSet(uint256 depositLimit);
    event MinValuesSet(
        uint256 oldMinDeposit,
        uint256 newMinDeposit,
        uint256 oldMinWithdrawal,
        uint256 newMinWithdrawal
    );
    event OperatorSet(
        address indexed controller,
        address indexed operator,
        bool approved
    );

    error InvalidAsset();
    error Duplicate();
    error NoMultisigs();
    error DebtLimitExceeded();
    error InvalidDebtLimit();
    error MultisigNotFound();
    error InsufficientMultisigBalance();
    error InvalidFee(uint256 fee);
    error PermitDeadlineExpired(uint256 deadline);
    error InvalidSigner(address signer);

    function initialize(
        IERC20 asset_,
        address owner_,
        address[] memory multisigAddresses,
        uint256[] memory debtLimits,
        uint256[] memory interestRates,
        uint256[] memory securityDeposits,
        uint256 depositLimit_
    ) public initializer {
        __BaseVaultStorage_init(
            asset_,
            owner_,
            string.concat(
                "VaultCraft ",
                IERC20Metadata(address(asset_)).name(),
                " Vault"
            ),
            string.concat("vc-", IERC20Metadata(address(asset_)).symbol())
        );

        if (address(asset_) == address(0)) revert InvalidAsset();
        if (multisigAddresses.length == 0) revert NoMultisigs();
        if (multisigAddresses.length != debtLimits.length) revert();

        for (uint256 i = 0; i < multisigAddresses.length; i++) {
            addMultisig(
                multisigAddresses[i],
                debtLimits[i],
                interestRates[i],
                securityDeposits[i]
            );
        }

        _setContractName(
            keccak256(
                abi.encodePacked(
                    "VaultCraft ",
                    name(),
                    block.timestamp,
                    "Vault"
                )
            )
        );

        emit VaultInitialized(contractName, address(asset_));
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @return Total amount of underlying `asset` token managed by vault. Delegates to adapter.
    function totalAssets() public view override returns (uint256) {
        // return oracle.getQuote(totalSupply(), address(this), asset());

        uint256 _totalAssets;
        address multisig = multisigs[SENTINEL_MULTISIG];
        for (uint256 i; i < multisigCount; i++) {
            DebtInfo memory _debtInfo = debtInfo[multisig];
            _totalAssets += IOracle(_debtInfo.oracle).getQuote(
                _debtInfo.currentDebt,
                address(this),
                asset()
            );
            multisig = multisigs[multisig];
        }
        return _totalAssets;
    }

    function multisigTotalAssets(
        address multisig
    ) public view returns (uint256) {
        DebtInfo memory _debtInfo = debtInfo[multisig];
        return
            IOracle(_debtInfo.oracle).getQuote(
                _debtInfo.currentDebt,
                address(this),
                asset()
            );
    }

    function convertToMultisigShares(
        address multisig,
        uint256 assets
    ) public view returns (uint256) {
        DebtInfo memory _debtInfo = debtInfo[multisig];

        return
            assets.mulDiv(
                _debtInfo.currentDebt,
                IOracle(_debtInfo.oracle).getQuote(
                    _debtInfo.currentDebt,
                    address(this),
                    asset()
                ),
                Math.Rounding.Floor
            );
    }

    function convertToMultisigAssets(
        address multisig,
        uint256 shares
    ) public view returns (uint256) {
        DebtInfo memory _debtInfo = debtInfo[multisig];

        return
            shares.mulDiv(
                IOracle(_debtInfo.oracle).getQuote(
                    _debtInfo.currentDebt,
                    address(this),
                    asset()
                ),
                _debtInfo.currentDebt,
                Math.Rounding.Floor
            );
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
        if (shares < minValue) revert();

        // If _asset is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            caller,
            address(this),
            assets
        );

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
                        REQUEST REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

    function requestRedeem(
        uint256 shares,
        address recipient,
        address owner
    ) external returns (uint256 requestId) {
        // TODO write error message
        if (shares < minValue) revert();

        SafeERC20.safeTransferFrom(this, owner, address(this), shares);

        address multisig = multisigs[SENTINEL_MULTISIG];

        for (uint256 i; i < multisigCount; i++) {
            DebtInfo memory _debtInfo = debtInfo[multisig];
            if (shares == 0) break;
            if (_debtInfo.currentDebt > 0) {
                uint256 redeemAmount = _debtInfo.currentDebt > shares
                    ? shares
                    : _debtInfo.currentDebt;
                shares -= redeemAmount;
                _requestRedeem(redeemAmount, recipient, owner, multisig);
            }
            multisig = multisigs[multisig];
        }
    }

    /// @notice this deposit request is added to any pending deposit request
    function requestRedeem(
        uint256 shares,
        address recipient,
        address owner,
        address multisig
    ) external returns (uint256 requestId) {
        // TODO write error message
        if (shares < minWithdrawal) revert();

        _requestRedeem(shares, recipient, owner, multisig);

        return REQUEST_ID;
    }

    function _requestRedeem(
        uint256 shares,
        address recipient,
        address owner,
        address multisig
    ) internal {
        require(
            owner == msg.sender || isOperator[owner][msg.sender],
            "ERC7540Vault/invalid-owner"
        );
        require(shares != 0, "ZERO_SHARES");

        SafeERC20.safeTransferFrom(this, owner, address(this), shares);

        _redeemRequests[recipient][multisig] = RedeemRequest({
            shares: shares + _redeemRequests[recipient][multisig].shares,
            requestTime: block.timestamp
        });
        _pendingRedeem[recipient] += shares;

        emit RedeemRequested(
            recipient,
            owner,
            REQUEST_ID,
            msg.sender,
            shares,
            block.timestamp
        );
    }

    /*//////////////////////////////////////////////////////////////
                        FULLFILLMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function fulfillWithShares(
        address recipient,
        uint256 shares
    ) public returns (uint256 assets) {
        assets = convertToAssets(shares);
        _fullfillRequest(
            recipient,
            assets.mulDiv(
                10_000 - withdrawalIncentive,
                10_000,
                Math.Rounding.Floor
            ),
            shares
        );
    }

    function fullfillWithAssets(
        address recipient,
        uint256 assets
    ) public returns (uint256 shares) {
        shares = convertToShares(assets);
        _fullfillRequest(
            recipient,
            assets.mulDiv(
                10_000 - withdrawalIncentive,
                10_000,
                Math.Rounding.Floor
            ),
            shares
        );
    }

    function _fullfillRequest(
        address recipient,
        uint256 assets,
        uint256 shares
    ) internal {
        RedeemRequest storage request = _redeemRequests[recipient][msg.sender];
        require(request.shares != 0, "ZERO_SHARES");

        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            msg.sender,
            address(this),
            assets
        );

        if (shares >= request.shares) {
            delete _redeemRequests[recipient][msg.sender];
        } else {
            request.shares -= shares;
        }

        _pendingRedeem[recipient] -= shares;

        _claimableRedeem[recipient].assets += assets;
        _claimableRedeem[recipient].shares += shares;

        debtInfo[msg.sender].currentDebt -= shares;

        _takeFees();
    }

    /*//////////////////////////////////////////////////////////////
                        PERMIT LOGIC
    //////////////////////////////////////////////////////////////*/

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

    // Additional functions from the original contract that need to be implemented...

    // Interactions:
    //  - Deposit / Mint
    //  - RequestRedeem
    //  - RequestRepayment
    //  - FulfillRedeem/Withdrawal
    //  - Withdraw / Redeem
    //  - PullFunds
}
