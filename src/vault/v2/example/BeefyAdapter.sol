// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {BaseAdapter, IERC20} from "../base/BaseAdapter.sol";
import {MathUpgradeable as Math} from "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IBeefyVault, IBeefyBooster, IBeefyBalanceCheck, IBeefyStrat} from "../../adapter/beefy/IBeefy.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

contract BeefyAdapter is BaseAdapter {
    using Math for uint256;

    IBeefyVault public beefyVault;
    IBeefyBooster public beefyBooster;
    IBeefyBalanceCheck public beefyBalanceCheck;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    error NotEndorsed(address beefyVault);
    error InvalidBeefyVault(address beefyVault);
    error InvalidBeefyBooster(address beefyBooster);
    error LpTokenNotSupported();

    function __BeefyAdapter_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        bool _useLpToken,
        IERC20[] memory _rewardTokens,
        address registry,
        bytes memory beefyInitData
    ) internal onlyInitializing {
        if (_useLpToken) revert LpTokenNotSupported();

        __BaseAdapter_init(_underlying, _lpToken, false, _rewardTokens);

        (address _beefyVault, address _beefyBooster) = abi.decode(
            beefyInitData,
            (address, address)
        );

        if (!IPermissionRegistry(registry).endorsed(_beefyVault))
            revert NotEndorsed(_beefyVault);
        if (
            _beefyBooster != address(0) &&
            !IPermissionRegistry(registry).endorsed(_beefyBooster)
        ) revert NotEndorsed(_beefyBooster);
        if (IBeefyVault(_beefyVault).want() != address(_underlying))
            revert InvalidBeefyVault(_beefyVault);
        if (
            _beefyBooster != address(0) &&
            IBeefyBooster(_beefyBooster).stakedToken() != _beefyVault
        ) revert InvalidBeefyBooster(_beefyBooster);

        beefyVault = IBeefyVault(_beefyVault);
        beefyBooster = IBeefyBooster(_beefyBooster);

        beefyBalanceCheck = IBeefyBalanceCheck(
            _beefyBooster == address(0) ? _beefyVault : _beefyBooster
        );

        _underlying.approve(_beefyVault, type(uint256).max);

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
        IBeefyStrat strat = IBeefyStrat(beefyVault.strategy());

        uint256 beefyFee;
        try strat.withdrawalFee() returns (uint256 _beefyFee) {
            beefyFee = _beefyFee;
        } catch {
            beefyFee = strat.withdrawFee();
        }
        uint256 assets = beefyBalanceCheck.balanceOf(address(this)).mulDiv(
            beefyVault.balance(),
            beefyVault.totalSupply(),
            Math.Rounding.Down
        );
        assets = assets.mulDiv(
            BPS_DENOMINATOR,
            BPS_DENOMINATOR - beefyFee,
            Math.Rounding.Down
        );
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits underlying asset and converts it if necessary into an lpToken before depositing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _depositUnderlying(uint256 amount) internal override {
        beefyVault.deposit(amount);
        if (address(beefyBooster) != address(0))
            beefyBooster.stake(beefyVault.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws underlying asset. If necessary it converts the lpToken into underlying before withdrawing
     * @dev This function must be overriden. Some farms require the user to into an lpToken before depositing others might use the underlying directly
     **/
    function _withdrawUnderlying(uint256 amount) internal override {
        if (address(beefyBooster) != address(0)) beefyBooster.withdraw(amount);
        beefyVault.withdraw(amount);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claims rewards
     */
    function _claimRewards() internal override {
        if (address(beefyBooster) == address(0)) return;

        try beefyBooster.getReward() {} catch {}
    }
}
