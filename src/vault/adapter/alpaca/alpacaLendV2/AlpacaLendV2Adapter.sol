// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {WithRewards, IWithRewards} from "../../abstracts/WithRewards.sol";
import {IAlpacaLendV2Vault, IAlpacaLendV2Manger, IAlpacaLendV2MiniFL, IAlpacaLendV2IbToken} from "./IAlpacaLendV2.sol";

/**
 * @title   AlpacaV2 Adapter
 * @author  amatureApe
 * @notice  ERC4626 wrapper for AlpacaV2 Vaults.
 *
 * An ERC4626 compliant Wrapper for Alpaca Lend V1.
 * Allows wrapping AlpacaV2 Vaults.
 */
contract AlpacaLendV2Adapter is AdapterBase, WithRewards {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Alpaca Lend V2 Manager contract
    IAlpacaLendV2Manger public alpacaManager;

    /// @notice The Alpaca Lend V2 MiniFL contract
    IAlpacaLendV2MiniFL public miniFL;

    /// @notice The Alpaca Lend V2 ibToken
    IAlpacaLendV2IbToken public ibToken;

    /// @notice PoolId corresponding to collateral in Alpaca Manger
    uint256 public pid;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error InvalidAsset();

    /**
     * @notice Initialize a new Alpaca Lend V2 Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry The manager contract for Alpaca Lend V2.
     * @param alpacaV2InitData Encoded data for the alpaca v2 initialization.
     * @dev The poolId for the ibToken in Alpaca Manager contract
     * @dev This function is called by the factory contract when deploying a new vault.
     */

    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory alpacaV2InitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        uint256 _pid = abi.decode(alpacaV2InitData, (uint256));

        alpacaManager = IAlpacaLendV2Manger(registry);
        miniFL = IAlpacaLendV2MiniFL(alpacaManager.miniFL());

        pid = _pid;
        ibToken = IAlpacaLendV2IbToken(miniFL.stakingTokens(_pid));

        if (ibToken.asset() != asset()) revert InvalidAsset();

        _name = string.concat(
            "VaultCraft AlpacaLendV2 ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcAlV2-", IERC20Metadata(asset()).symbol());

        IERC20(ibToken.asset()).approve(
            address(alpacaManager),
            type(uint256).max
        );
        IERC20(address(ibToken)).approve(
            address(alpacaManager),
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
        uint256 assets = ibToken.convertToAssets(
            ibToken.balanceOf(address(this))
        );

        return assets;
    }

    /// @notice The amount of beefy shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256 assets,
        uint256 shares
    ) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    ibToken.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Up
                );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint256 amount, uint256) internal override {
        alpacaManager.deposit(address(asset()), amount);
    }

    function _protocolWithdraw(
        uint256 amount,
        uint256 shares
    ) internal override {
        uint256 alpacaShares = convertToUnderlyingShares(0, shares);

        alpacaManager.withdraw(address(ibToken), alpacaShares);
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
