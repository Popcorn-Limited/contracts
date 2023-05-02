// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {IAlpacaLendV1Vault} from "./IAlpacaLendV1.sol";

/**
 * @title   AlpacaV1 Adapter
 * @notice  ERC4626 wrapper for AlpacaV1 Vaults.
 *
 * An ERC4626 compliant Wrapper for Alpaca Lend V1.
 * Allows wrapping AlpacaV1 Vaults.
 */
contract AlpacaLendV1Adapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Alpaca Lend V1 Vault contract
    IAlpacaLendV1Vault public alpacaVault;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new MasterChef Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev `_pid` - The poolId for lpToken.
     * @dev `_rewardsToken` - The token rewarded by the MasterChef contract (Sushi, Cake...)
     * @dev This function is called by the factory contract when deploying a new vault.
     */

    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory alpacaV1InitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        address _vault = abi.decode(alpacaV1InitData, (address));

        alpacaVault = IAlpacaLendV1Vault(_vault);

        if (alpacaVault.token() != asset()) revert InvalidAsset();

        _name = string.concat(
            "VaultCraft AlpacaLendV1 ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcAlV1-", IERC20Metadata(asset()).symbol());

        IERC20(alpacaVault.token()).approve(
            address(alpacaVault),
            type(uint256).max
        );
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
            (alpacaVault.balanceOf(address(this)) * alpacaVault.totalToken()) /
            alpacaVault.totalSupply();
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        alpacaVault.deposit(amount);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256 shares
    ) internal override {
        uint256 alpacaShares = convertToUnderlyingShares(0, shares);

        alpacaVault.withdraw(alpacaShares);
    }

    /// @notice The amount of alapacaV1 shares to withdraw given an mount of adapter shares
    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    alpacaVault.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
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
