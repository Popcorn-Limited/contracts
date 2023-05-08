// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../../abstracts/AdapterBase.sol";
import {IAuroraStNear} from "./IAuroraStNear.sol";

/**
 * @title   Staked Near Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for Metapool stNear Vault.
 *
 * An ERC4626 compliant Wrapper for https://github.com/Narwallets/aurora-swap/blob/master/contracts/AuroraStNear.sol.
 * Allows wrapping Metapool stNear.
 */
contract StakedNearAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The aurora stNear converter contract.
    IAuroraStNear public auroraStNear;

    /// @notice The aurora stNear contract.
    IERC20 public stNear;

    /// @notice Used for raising / dividing stNear or wNear amounts since they use 24 decimals
    uint256 internal constant SCALAR = 1e24;

    /// @notice Used to calculcate fees as they are calculated in 10_000 Basis Points
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Metapool stNear Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The aurora stNear staker.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        if (IAuroraStNear(registry).wNear() != asset()) revert InvalidAsset();

        auroraStNear = IAuroraStNear(registry);
        stNear = IERC20(IAuroraStNear(registry).stNear());

        _name = string.concat(
            "VaultCraft stNear ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcSt-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(registry, type(uint256).max);
        stNear.approve(registry, type(uint256).max);
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

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.

    function _totalAssets() internal view override returns (uint256) {
        return
            stNear.balanceOf(address(this)).mulDiv(
                auroraStNear.stNearPrice(),
                SCALAR,
                Math.Rounding.Down
            );
    }

    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        return
            paused()
                ? 0
                : _convertToShares(
                    assets - _getDepositFee(assets),
                    Math.Rounding.Down
                );
    }

    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        if (paused()) return 0;

        uint256 assets = _convertToAssets(shares, Math.Rounding.Up);
        return assets + _getDepositFee(assets);
    }

    function previewWithdraw(
        uint256 assets
    ) public view override returns (uint256) {
        return
            _convertToShares(
                assets.mulDiv(
                    BPS_DENOMINATOR,
                    BPS_DENOMINATOR - auroraStNear.wNearSwapFee(),
                    Math.Rounding.Down
                ),
                Math.Rounding.Up
            );
    }

    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Down);
        return
            assets.mulDiv(
                BPS_DENOMINATOR - auroraStNear.wNearSwapFee(),
                BPS_DENOMINATOR,
                Math.Rounding.Down
            );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _getDepositFee(uint256 amount) internal view returns (uint256) {
        uint256 stNearAmount = (amount * SCALAR) / auroraStNear.stNearPrice();

        return (stNearAmount * auroraStNear.stNearSwapFee()) / BPS_DENOMINATOR;
    }

    function _protocolDeposit(uint256 amount, uint256) internal override {
        auroraStNear.swapwNEARForstNEAR(amount);
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        auroraStNear.swapstNEARForwNEAR(
            amount.mulDiv(SCALAR, auroraStNear.stNearPrice(), Math.Rounding.Up)
        );
    }
}
