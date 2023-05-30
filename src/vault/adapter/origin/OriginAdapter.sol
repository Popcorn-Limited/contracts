// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../abstracts/AdapterBase.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

/**
 * @title   Origin Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for Origin Vault.
 *
 * An ERC4626 compliant Wrapper for .
 * Allows wrapping Ousd.
 */
contract OriginAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The wrapped oToken contract.
    IERC4626 public wAsset;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed();
    error InvalidAsset();

    /**
     * @notice Initialize a new MasterChef Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_wAsset` - The address of the wrapped asset.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory ousdInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        address _wAsset = abi.decode(ousdInitData, (address));

        if (!IPermissionRegistry(registry).endorsed(_wAsset))
            revert NotEndorsed();
        if (IERC4626(_wAsset).asset() != asset()) revert InvalidAsset();

        wAsset = IERC4626(_wAsset);

        _name = string.concat(
            "VaultCraft Origin ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcO-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(wAsset), type(uint256).max);
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
        return wAsset.convertToAssets(wAsset.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        wAsset.deposit(amount, address(this));
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        wAsset.withdraw(amount, address(this), address(this));
    }
}
