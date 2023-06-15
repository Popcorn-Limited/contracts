// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {IMetaPool} from "./IMetaPool.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

/**
 * @title   MetaPool Adapter
 * @author  0xSolDev
 * @notice  ERC4626 wrapper for MetaPool Vaults.
 *
 */
contract MetaPoolAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMetaPool public iPool;
    IERC20Metadata public stNear;
    IERC20Metadata public wNear;

    uint256 internal constant stNearDecimals = 24;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    error NotValidCDO(address cdo);
    error PausedCDO(address cdo);
    error NotValidAsset(address asset);

    /**
     * @notice Initialize a new Meta Pool Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the Meta Pool adapter is endorsed.
     * @param metaInitData Encoded data for the Meta Pool adapter initialization.
     * @dev _cdo address of the CDO contract
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory metaInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        iPool = IMetaPool(registry);

        if (address(iPool.wNear()) != asset()) revert NotValidAsset(asset());

        stNear = iPool.stNear();
        wNear = iPool.wNear();

        _name = string.concat(
            "VaultCraft MetaPool ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcM-", IERC20Metadata(asset()).symbol());

        IERC20(wNear).safeApprove(registry, type(uint256).max);
        IERC20(stNear).safeApprove(registry, type(uint256).max);
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
            (stNear.balanceOf(address(this)) *
                (BPS_DENOMINATOR - iPool.wNearSwapFee()) *
                iPool.stNearPrice()) /
            BPS_DENOMINATOR /
            (10 ** stNearDecimals);
    }

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    stNear.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    // /// @notice Applies the idle deposit limit to the adapter.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;

        uint256 stNearAmount = (IERC20(stNear).balanceOf(address(iPool)) *
            (BPS_DENOMINATOR - iPool.stNearSwapFee())) / BPS_DENOMINATOR; // Swap fees in basis points. 10000 == 100%

        return (stNearAmount * iPool.stNearPrice()) / (10 ** stNearDecimals);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 amount = convertToAssets(balanceOf(owner));

        uint256 wNearAmount = (IERC20(wNear).balanceOf(address(iPool)) *
            (BPS_DENOMINATOR - iPool.wNearSwapFee())) / BPS_DENOMINATOR; // Swap fees in basis points. 10000 == 100%

        uint256 maxAmount = (wNearAmount * (10 ** stNearDecimals)) /
            iPool.stNearPrice();

        return amount > maxAmount ? maxAmount : amount;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into Meta Pool and optionally into the booster given its configured
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        iPool.swapwNEARForstNEAR(amount);
    }

    /// @notice Withdraw from the Meta Pool and optionally from the booster given its configured
    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        uint256 shares = convertToShares(amount);
        uint256 underlyingShare = convertToUnderlyingShares(0, shares);
        iPool.swapstNEARForwNEAR(underlyingShare);
    }
}
