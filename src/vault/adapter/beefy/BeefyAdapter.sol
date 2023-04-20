// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IBeefyVault, IBeefyBooster, IBeefyBalanceCheck, IBeefyStrat} from "./IBeefy.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

/**
 * @title   Beefy Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Beefy Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/beefyfinance/beefy-contracts/blob/master/contracts/BIFI/vaults/BeefyVaultV6.sol.
 * Allows wrapping Beefy Vaults with or without an active Booster.
 * Allows for additional strategies to use rewardsToken in case of an active Booster.
 */
contract BeefyAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IBeefyVault public beefyVault;
    IBeefyBooster public beefyBooster;
    IBeefyBalanceCheck public beefyBalanceCheck;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    error NotEndorsed(address beefyVault);
    error InvalidBeefyVault(address beefyVault);
    error InvalidBeefyBooster(address beefyBooster);

    /**
     * @notice Initialize a new Beefy Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the beefy adapter is endorsed.
     * @param beefyInitData Encoded data for the beefy adapter initialization.
     * @dev `_beefyVault` - The underlying beefy vault.
     * @dev `_beefyBooster` - An optional beefy booster.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory beefyInitData
    ) external initializer {
        (address _beefyVault, address _beefyBooster) = abi.decode(
            beefyInitData,
            (address, address)
        );
        __AdapterBase_init(adapterInitData);

        if (!IPermissionRegistry(registry).endorsed(_beefyVault))
            revert NotEndorsed(_beefyVault);
        if (
            _beefyBooster != address(0) &&
            !IPermissionRegistry(registry).endorsed(_beefyBooster)
        ) revert NotEndorsed(_beefyBooster);
        if (IBeefyVault(_beefyVault).want() != asset())
            revert InvalidBeefyVault(_beefyVault);
        if (
            _beefyBooster != address(0) &&
            IBeefyBooster(_beefyBooster).stakedToken() != _beefyVault
        ) revert InvalidBeefyBooster(_beefyBooster);

        _name = string.concat(
            "VaultCraft Beefy ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcB-", IERC20Metadata(asset()).symbol());

        beefyVault = IBeefyVault(_beefyVault);
        beefyBooster = IBeefyBooster(_beefyBooster);

        beefyBalanceCheck = IBeefyBalanceCheck(
            _beefyBooster == address(0) ? _beefyVault : _beefyBooster
        );

        IERC20(asset()).approve(_beefyVault, type(uint256).max);

        if (_beefyBooster != address(0))
            IERC20(_beefyVault).approve(_beefyBooster, type(uint256).max);
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
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function _totalAssets() internal view override returns (uint256) {
        return
            beefyBalanceCheck.balanceOf(address(this)).mulDiv(
                beefyVault.balance(),
                beefyVault.totalSupply(),
                Math.Rounding.Down
            );
    }

    /// @notice The amount of beefy shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    beefyBalanceCheck.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    /// @notice The token rewarded if a beefy booster is configured
    function rewardTokens()
        external
        view
        override
        returns (address[] memory _rewardTokens)
    {
        _rewardTokens = new address[](1);
        if (address(beefyBooster) != address(0))
            _rewardTokens[0] = beefyBooster.rewardToken();
    }

    /// @notice `previewWithdraw` that takes beefy withdrawal fees into account
    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        IBeefyStrat strat = IBeefyStrat(beefyVault.strategy());

        uint256 beefyFee;
        try strat.withdrawalFee() returns (uint256 _beefyFee) {
            beefyFee = _beefyFee;
        } catch {
            beefyFee = strat.withdrawFee();
        }

        if (beefyFee > 0)
            assets = assets.mulDiv(
                BPS_DENOMINATOR,
                BPS_DENOMINATOR - beefyFee,
                Math.Rounding.Down
            );

        return _convertToShares(assets, Math.Rounding.Up);
    }

    /// @notice `previewRedeem` that takes beefy withdrawal fees into account
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Down);

        IBeefyStrat strat = IBeefyStrat(beefyVault.strategy());

        uint256 beefyFee;
        try strat.withdrawalFee() returns (uint256 _beefyFee) {
            beefyFee = _beefyFee;
        } catch {
            beefyFee = strat.withdrawFee();
        }

        if (beefyFee > 0)
            assets = assets.mulDiv(
                BPS_DENOMINATOR - beefyFee,
                BPS_DENOMINATOR,
                Math.Rounding.Down
            );

        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into beefy vault and optionally into the booster given its configured
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        beefyVault.deposit(amount);
        if (address(beefyBooster) != address(0))
            beefyBooster.stake(beefyVault.balanceOf(address(this)));
    }

    /// @notice Withdraw from the beefy vault and optionally from the booster given its configured
    function _protocolWithdraw(
        uint256,
        uint256 shares
    ) internal virtual override {
        uint256 beefyShares = convertToUnderlyingShares(0, shares);

        if (address(beefyBooster) != address(0))
            beefyBooster.withdraw(beefyShares);
        beefyVault.withdraw(beefyShares);
    }

    /*//////////////////////////////////////////////////////////////
                            STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards from the beefy booster given its configured
    function claim() public override onlyStrategy returns (bool success) {
        if (address(beefyBooster) == address(0)) return false;
        try beefyBooster.getReward() {
            success = true;
        } catch {}
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-165 LOGIC
  //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 interfaceId
    ) public pure override(WithRewards, AdapterBase) returns (bool) {
        return
            interfaceId == type(IWithRewards).interfaceId ||
            interfaceId == type(IAdapter).interfaceId;
    }
}
