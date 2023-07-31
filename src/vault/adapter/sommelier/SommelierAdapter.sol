// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../abstracts/WithRewards.sol";
import {IVault} from "./ISommelier.sol";

/**
 * @title   Sommelier Adapter
 * @notice  ERC4626 wrapper for Sommelier Vaults.
 *
 * An ERC4626 compliant Wrapper for Sommelier Vaults
 * Allows wrapping Sommelier Vaults.
 */
contract SommelierAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // @notice The Sommelier vault
    IVault public vault;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Sommelier Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev `_rewardsToken` - The token rewarded by the Sommelier contract (Sushi, Cake...)
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory sommelierInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        address _vault = abi.decode(sommelierInitData, (address));

        vault = IVault(_vault);

        if (vault.asset() != asset()) revert InvalidAsset();

        _name = string.concat(
            "VaultCraft Sommelier ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcSomm-", IERC20Metadata(asset()).symbol());

        IERC20(vault.asset()).approve(address(vault), type(uint256).max);
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
    error PING(uint256 x, uint256 y);

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.

    function _totalAssets() internal view override returns (uint256) {
        uint256 shares = vault.balanceOf(address(this));
        uint256 assets = vault.convertToAssets(shares);
        return assets;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/
    function _protocolDeposit(uint256 amount, uint256) internal override {
        vault.deposit(amount, address(this));
    }

    error DING();

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        uint256 shares = vault.convertToShares(amount);

        // revert PING(amount, shares);

        vault.redeem(shares, address(this), address(this));
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
