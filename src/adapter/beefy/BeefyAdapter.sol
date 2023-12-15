// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeERC20Upgradeable as SafeERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {BaseAdapter, IERC20, AdapterConfig} from "../../base/BaseAdapter.sol";
import {IBeefyVault, IBeefyBooster, IBeefyBalanceCheck, IBeefyStrat} from "./IBeefy.sol";
import {IPermissionRegistry} from "../../base/interfaces/IPermissionRegistry.sol";

contract BeefyAdapter is BaseAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IBeefyVault public beefyVault;
    IBeefyBooster public beefyBooster;
    IBeefyBalanceCheck public beefyBalanceCheck;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    error NotEndorsed(address beefyContract);
    error InvalidBeefyVault(address beefyVault);
    error InvalidBeefyBooster(address beefyBooster);
    error LpTokenNotSupported();

    function __BeefyAdapter_init(
        AdapterConfig memory _adapterConfig
    ) internal onlyInitializing {
        if (_adapterConfig.useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_adapterConfig);

        (address _beefyVault, address _beefyBooster) = abi.decode(
            _adapterConfig.protocolData,
            (address, address)
        );

        // @dev permissionRegistry of eth
        // @dev change the registry address depending on the deployed chain
        if (
            !IPermissionRegistry(0x7a33b5b57C8b235A3519e6C010027c5cebB15CB4)
                .endorsed(_beefyVault)
        ) revert NotEndorsed(_beefyVault);
        if (
            _beefyBooster != address(0) &&
            !IPermissionRegistry(0x7a33b5b57C8b235A3519e6C010027c5cebB15CB4)
                .endorsed(_beefyBooster)
        ) revert NotEndorsed(_beefyBooster);

        if (
            IBeefyVault(_beefyVault).want() !=
            address(_adapterConfig.underlying)
        ) revert InvalidBeefyVault(_beefyVault);
        if (
            _beefyBooster != address(0) &&
            IBeefyBooster(_beefyBooster).stakedToken() != _beefyVault
        ) revert InvalidBeefyBooster(_beefyBooster);

        beefyVault = IBeefyVault(_beefyVault);
        beefyBooster = IBeefyBooster(_beefyBooster);

        beefyBalanceCheck = IBeefyBalanceCheck(
            _beefyBooster == address(0) ? _beefyVault : _beefyBooster
        );

        _adapterConfig.underlying.approve(_beefyVault, type(uint256).max);

        if (_beefyBooster != address(0))
            IERC20(_beefyVault).approve(_beefyBooster, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets.
     * @dev This function must be overriden. If the farm requires the usage of lpToken than this function must convert lpToken balance into underlying balance
     */
    function _totalUnderlying() internal view override returns (uint256) {
        uint beefyFee = _getBeefyWithdrawalFee();

        uint256 assets = beefyBalanceCheck.balanceOf(address(this)).mulDiv(
            beefyVault.balance(),
            beefyVault.totalSupply(),
            Math.Rounding.Down
        );
        assets = assets.mulDiv(
            BPS_DENOMINATOR - beefyFee,
            BPS_DENOMINATOR,
            Math.Rounding.Down
        );
        return assets;
    }

    function _totalLP() internal pure override returns (uint) {
        revert("NO");
    }

    // converts assets to beefy vault shares
    function _convertAssetsToShares(uint assets) internal view returns (uint) {
        return
            assets.mulDiv(
                1e18,
                beefyVault.getPricePerFullShare(),
                Math.Rounding.Up
            );
    }

    function _getBeefyWithdrawalFee() internal view returns (uint fee) {
        IBeefyStrat strat = IBeefyStrat(beefyVault.strategy());

        try strat.withdrawalFee() returns (uint256 _beefyFee) {
            fee = _beefyFee;
        } catch {
            fee = strat.withdrawFee();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _deposit(uint256 amount, address caller) internal override {
        if (caller != address(this))
            underlying.safeTransferFrom(caller, address(this), amount);
        _depositUnderlying(amount);
    }

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        beefyVault.deposit(amount);
        if (address(beefyBooster) != address(0))
            beefyBooster.stake(beefyVault.balanceOf(address(this)));
    }

    function _depositLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _withdraw(uint256 amount, address receiver) internal override {
        if (!paused()) _withdrawUnderlying(amount);
        underlying.safeTransfer(receiver, amount);
    }

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        /// @dev because we want to withdraw exactly `amount` we have to take into account the fees
        // we have to pay when caclulating the share amount we'll send to the beefy vault.
        uint amountWithFees = amount.mulDiv(
            BPS_DENOMINATOR,
            BPS_DENOMINATOR - _getBeefyWithdrawalFee(),
            Math.Rounding.Down
        );
        uint shares = _convertAssetsToShares(amountWithFees);
        if (address(beefyBooster) != address(0)) beefyBooster.withdraw(shares);
        beefyVault.withdraw(shares);
    }

    function _withdrawLP(uint) internal pure override {
        revert("NO");
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claim() internal override {
        if (address(beefyBooster) == address(0)) return;

        try beefyBooster.getReward() {} catch {}
    }
}
