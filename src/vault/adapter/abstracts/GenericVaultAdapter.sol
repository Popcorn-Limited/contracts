// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter, IERC4626} from "../abstracts/AdapterBase.sol";
import {IPermissionRegistry} from "../../../interfaces/vault/IPermissionRegistry.sol";

/**
 * @title   ERC4626 Vauöt Adapter
 * @author  RedVeil
 * @notice  ERC4626 wrapper for any generic ERC4626 Vault.
 *
 * An ERC4626 compliant Wrapper for any generic vault following the EIP-4626 standard https://eips.ethereum.org/EIPS/eip-4626.
 */
contract GenericVaultAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IERC4626 public vault;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error NotEndorsed();
    error InvalidAsset();

    /**
     * @notice Initialize a new generic Vault Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_vault` - The address of the 4626 vault to use.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory vaultInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        
        address _vault = abi.decode(vaultInitData, (address));

        if (!IPermissionRegistry(registry).endorsed(_vault))
            revert NotEndorsed();
        if (IERC4626(_vault).asset() != asset()) revert InvalidAsset();

        vault = IERC4626(_vault);

        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).approve(address(vault), type(uint256).max);
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

    function _totalAssets() internal view virtual override returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        vault.deposit(amount, address(this));
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        vault.withdraw(amount, address(this), address(this));
    }
}
