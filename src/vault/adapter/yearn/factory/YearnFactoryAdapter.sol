// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {YearnAdapter, IERC20, IERC20Metadata, SafeERC20, Math} from "../YearnAdapter.sol";
import {IVaultFactory, VaultAPI} from "../IYearn.sol";

/**
 * @title   Yearn Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Yearn Vaults.
 *
 * An ERC4626 compliant Wrapper for https://github.com/yearn/yearn-vaults/blob/master/contracts/Vault.vy.
 * Allows wrapping Yearn Vaults.
 */
contract YearnFactoryAdapter is YearnAdapter {
    using SafeERC20 for IERC20;
    using Math for uint256;

    error InvalidAsset();

    /**
     * @notice Initialize a new Yearn Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param externalRegistry Yearn registry address.
     * @param yearnData init data for the yVault factory adapter
     * @dev `gauge` - Curve/Bal gauge that gets auto compounded.
     * @dev `maxLoss` - maxLoss for yVault.
     * @dev This function is called by the factory contract when deploying a new vault.
     * @dev The yearn registry will be used given the `asset` from `adapterInitData` to find the latest yVault.
     */
    function initialize(
        bytes memory adapterInitData,
        address externalRegistry,
        bytes memory yearnData
    ) external override initializer {
        __AdapterBase_init(adapterInitData);

        (address _gauge, uint256 _maxLoss) = abi.decode(
            yearnData,
            (address, uint256)
        );

        yVault = VaultAPI(
            IVaultFactory(externalRegistry).latestStandardVaultFromGauge(_gauge)
        );
        maxLoss = _maxLoss;

        if (yVault.token() != asset()) revert InvalidAsset();
        if (maxLoss > 10_000) revert MaxLossTooHigh();

        _name = string.concat(
            "VaultCraft Yearn ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcY-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(yVault), type(uint256).max);
    }

    /**
     * @notice Returns the total quantity of all assets under control of this Vault,
     * whether they're loaned out to a Strategy, or currently held in the Vault.
     */
    function _totalAssets() internal view override returns (uint256) {
        return
            // yVault.balanceOf(address(this)).mulDiv(
            //     yVault.totalAssets(),
            //     yVault.totalSupply(),
            //     Math.Rounding.Down
            // );
            yVault.balanceOf(address(this)).mulDiv(
                yVault.pricePerShare(),
                1e18,
                Math.Rounding.Down
            );
    }

    // /// @notice The amount of aave shares to withdraw given an mount of adapter shares
    // function convertToUnderlyingShares(
    //     uint256 assets,
    //     uint256
    // ) public view override returns (uint256) {
    //     return
    //         assets.mulDiv(
    //             yVault.totalSupply(),
    //             yVault.totalAssets(),
    //             Math.Rounding.Up
    //         );
    // }
}
