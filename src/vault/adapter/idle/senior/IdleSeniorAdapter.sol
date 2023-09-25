// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../../abstracts/AdapterBase.sol";
import {IIdleCDO, IRegistry} from "../IIdle.sol";

/**
 * @title   Idle Senior Adapter
 * @author  0xSolDev
 * @notice  ERC4626 wrapper for Idle Vaults.
 *
 * An ERC4626 compliant Wrapper for https://app.idle.finance/#/earn/yield-tranches.
 * Allows wrapping IDLE Vaults with senior tranches.
 */
contract IdleSeniorAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IIdleCDO public cdo;

    error NotValidCDO(address cdo);
    error PausedCDO(address cdo);
    error NotValidAsset(address asset);

    /**
     * @notice Initialize a new IDLE Adapter.
     * @param adapterInitData Encoded data for the base adapter initialization.
     * @param registry Endorsement Registry to check if the idle adapter is endorsed.
     * @param idleInitData Encoded data for the idle adapter initialization.
     * @dev _cdo address of the CDO contract
     * @dev This function is called by the factory contract when deploying a new vault.
     */
    function initialize(
        bytes memory adapterInitData,
        address registry,
        bytes memory idleInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        address _cdo = abi.decode(idleInitData, (address));

        if (!IRegistry(registry).isValidCdo(_cdo)) revert NotValidCDO(_cdo);
        if (IIdleCDO(_cdo).paused()) revert PausedCDO(_cdo);
        if (IIdleCDO(_cdo).token() != asset()) revert NotValidAsset(asset());

        IRegistry _registry = IRegistry(registry);
        cdo = IIdleCDO(_cdo);

        _name = string.concat(
            "VaultCraft Idle Senior ",
            IERC20Metadata(asset()).name(),
            " Adapter"
        );
        _symbol = string.concat("vcIdlS-", IERC20Metadata(asset()).symbol());

        IERC20(asset()).safeApprove(_cdo, type(uint256).max);
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
        address tranche = cdo.AATranche();
        return
            IERC20(tranche).balanceOf(address(this)).mulDiv(
                cdo.tranchePrice(tranche),
                cdo.ONE_TRANCHE_TOKEN(),
                Math.Rounding.Down
            );
    }

    /// @notice The amount of ellipsis shares to withdraw given an amount of adapter shares
    function convertToUnderlyingShares(
        uint256,
        uint256 shares
    ) public view override returns (uint256) {
        address tranche = cdo.AATranche();
        uint256 balance = IERC20(tranche).balanceOf(address(this));

        uint256 supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(balance, supply, Math.Rounding.Up);
    }

    /// @notice Applies the idle deposit limit to the adapter.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 _depositLimit = cdo.limit();
        if (_depositLimit == 0) {
            return type(uint256).max;
        }
        uint256 assets = cdo.getContractValue();
        if (assets >= _depositLimit) return 0;
        return _depositLimit - assets;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into Idle vault and optionally into the booster given its configured
    function _protocolDeposit(
        uint256 amount,
        uint256
    ) internal virtual override {
        cdo.depositAARef(amount, FEE_RECIPIENT);
    }

    /// @notice Withdraw from the Idle vault and optionally from the booster given its configured
    function _protocolWithdraw(
        uint256 amount,
        uint256
    ) internal virtual override {
        address tranche = cdo.AATranche();
        uint256 balance = IERC20(tranche).balanceOf(address(this));
        uint256 shares = convertToShares(amount);
        uint256 underlayingShares = convertToUnderlyingShares(0, shares);
        cdo.withdrawAA(underlayingShares);
    }
}
