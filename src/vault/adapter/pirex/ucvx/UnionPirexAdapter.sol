// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;
import {IUnionPirexVault} from "./IUnionPirexVault.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IAdapter} from "../../abstracts/AdapterBase.sol";


contract UnionPirexAdapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    // @notice The Union Pirex vault
    IUnionPirexVault public vault;

    error InvalidAsset();
    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Initialize the new Union Pirex Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory unionPirexInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        address _vault = abi.decode(unionPirexInitData, (address));
        vault = IUnionPirexVault(_vault);

        if (vault.asset() != asset()) revert InvalidAsset();

        _name = string.concat(
            "VaultCraft Union Pirex ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vc-uCVX-", IERC20Metadata(asset()).symbol());

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

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    /// @notice previewRedeem is used here as opposed to covertToAssets
    ///         because the vault takes a withdrawal penalty from the
    ///         shares of the to fulfill withdrawal.
    function _totalAssets() internal view override returns (uint256) {
        return vault.previewRedeem(vault.balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/
    function _protocolDeposit(uint256 amount, uint256) internal override {
        vault.deposit(amount, address(this));
    }

    function _protocolWithdraw(uint256 amount, uint256) internal override {
        vault.withdraw(amount, address(this), address(this));
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
