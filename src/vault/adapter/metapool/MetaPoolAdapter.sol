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
 * An ERC4626 compliant Wrapper for https://app.idle.finance/#/earn/yield-tranches.
 * Allows wrapping MetaPool Vaults with junior tranches.
 */
contract MetaPoolAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IMetaPool public iPool;
    IERC20Metadata public stNear;
    IERC20Metadata public wNear;

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
        uint256 stNearDecimals = stNear.decimals();
        // aurora testnet bug
        if (stNearDecimals == 0){
            stNearDecimals = 24;
        }

        uint16 wNearSwapFee = iPool.wNearSwapFee();

        uint256 stNearBalance = stNear.balanceOf(address(this));
        return stNearBalance * (10000 - wNearSwapFee) * iPool.stNearPrice() / 10000 / (10 ** stNearDecimals);
    }

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(uint256, uint256 shares) public view override returns (uint256) {
        uint256 stNearBalance = stNear.balanceOf(address(this));
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDiv(stNearBalance, supply, Math.Rounding.Up);
    }

    // /// @notice Applies the idle deposit limit to the adapter.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;

        uint256 totalStNear = IERC20(stNear).balanceOf(address(iPool));

        uint256 stNearDecimals = stNear.decimals();
        // aurora testnet bug
        if (stNearDecimals == 0){
            stNearDecimals = 24;
        }

        uint16 stNearSwapFee = iPool.stNearSwapFee();

        uint256 stNearAmount = totalStNear * (10000 - stNearSwapFee) / 10000;     // Swap fees in basis points. 10000 == 100%

        uint256 stNearPrice = iPool.stNearPrice();

        return stNearAmount * stNearPrice / (10 ** stNearDecimals);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {

        uint256 totalwNear = IERC20(wNear).balanceOf(address(iPool));

        uint256 amount = convertToAssets(balanceOf(owner));

        uint256 stNearDecimals = stNear.decimals();
        // aurora testnet bug
        if (stNearDecimals == 0){
            stNearDecimals = 24;
        }

        uint16 wNearSwapFee = iPool.wNearSwapFee();

        uint256 wNearAmount = totalwNear * (10000 - wNearSwapFee) / 10000;     // Swap fees in basis points. 10000 == 100%

        uint256 stNearPrice = iPool.stNearPrice();

        uint256 maxAmount = wNearAmount * (10 ** stNearDecimals) / stNearPrice;

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