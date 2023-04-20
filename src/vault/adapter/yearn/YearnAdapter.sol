// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, ERC4626Upgradeable as ERC4626, IERC20, IERC20Metadata, ERC20, SafeERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {VaultAPI, IYearnRegistry} from "./IYearn.sol";

/**
 * @title   Yearn Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Yearn Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/yearn/yearn-vaults/blob/master/contracts/Vault.vy.
 * Allows wrapping Yearn Vaults.
 */
contract YearnAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    VaultAPI public yVault;
    uint256 public maxLoss;

    uint256 constant DEGRADATION_COEFFICIENT = 10 ** 18;

    error MaxLossTooHigh();

    /**
     * @notice Initialize a new Yearn Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param externalRegistry Yearn registry address.
     * @param yearnData `MaxLoss` for yVault encoded in bytes.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev The yearn registry will be used given the `asset` from `adapterInitData` to find the latest yVault.
     */
    function initialize(
        bytes memory adapterInitData,
        address externalRegistry,
        bytes memory yearnData
    ) external initializer {
        (address _asset, , , , , ) = abi.decode(
            adapterInitData,
            (address, address, address, uint256, bytes4[8], bytes)
        );
        __AdapterBase_init(adapterInitData);

        yVault = VaultAPI(IYearnRegistry(externalRegistry).latestVault(_asset));

        _name = string.concat(
            "VaultCraft Yearn ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcY-", IERC20Metadata(asset()).symbol());

        maxLoss = abi.decode(yearnData, (uint256));
        if (maxLoss > 10_000) revert MaxLossTooHigh();

        IERC20(_asset).approve(address(yVault), type(uint256).max);
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

    /// @notice Emulate yearns total asset calculation to return the total assets of the vault.
    function _totalAssets() internal view override returns (uint256) {
        return _shareValue(yVault.balanceOf(address(this)));
    }

    /// @notice Determines the current value of `yShares` in assets
    function _shareValue(uint256 yShares) internal view returns (uint256) {
        if (yVault.totalSupply() == 0) return yShares;

        return
            yShares.mulDiv(
                _freeFunds(),
                yVault.totalSupply(),
                Math.Rounding.Down
            );
    }

    /// @notice The amount of assets that are free to be withdrawn from the yVault after locked profts.
    function _freeFunds() internal view returns (uint256) {
        return _yTotalAssets() - _calculateLockedProfit();
    }

    /**
     * @notice Returns the total quantity of all assets under control of this Vault,
     * whether they're loaned out to a Strategy, or currently held in the Vault.
     */
    function _yTotalAssets() internal view returns (uint256) {
        return IERC20(asset()).balanceOf(address(yVault)) + yVault.totalDebt();
    }

    /// @notice Calculates how much profit is locked and cant be withdrawn.
    function _calculateLockedProfit() internal view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - yVault.lastReport()) *
            yVault.lockedProfitDegradation();

        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            uint256 lockedProfit = yVault.lockedProfit();
            return
                lockedProfit -
                ((lockedFundsRatio * lockedProfit) / DEGRADATION_COEFFICIENT);
        } else {
            return 0;
        }
    }

    /// @notice The amount of aave shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    yVault.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return paused() ? 0 : _convertToShares(assets - 0, Math.Rounding.Down);
    }

    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        return paused() ? 0 : _convertToAssets(shares + 0, Math.Rounding.Up);
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return _convertToShares(assets + 0, Math.Rounding.Up);
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return _convertToAssets(shares - 0, Math.Rounding.Down);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAWAL LIMIT LOGIC
  //////////////////////////////////////////////////////////////*/

    /// @notice Applies the yVault deposit limit to the adapter.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;

        VaultAPI _bestVault = yVault;
        uint256 assets = _bestVault.totalAssets();
        uint256 _depositLimit = _bestVault.depositLimit();
        if (assets >= _depositLimit) return 0;
        return _depositLimit - assets;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        yVault.deposit(amount);
    }

    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        yVault.withdraw(
            convertToUnderlyingShares(assets, shares),
            address(this),
            maxLoss
        );
    }
}
