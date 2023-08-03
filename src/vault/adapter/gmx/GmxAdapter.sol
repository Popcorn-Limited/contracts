// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IStrategy, IAdapter} from "../abstracts/AdapterBase.sol";
import { IRewardRouterV2 } from "./IRewardRouterV2.sol";
import { IRewardTracker } from "./IRewardTracker.sol";

contract GmxAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    IRewardRouterV2 public router;

    IERC20 public gmx;

    function initialize(
        bytes memory adapterInitData,
        address _rewardRouterAddress,
        bytes memory _bytes
    ) public initializer {
        __AdapterBase_init(adapterInitData);

        router = IRewardRouterV2(_rewardRouterAddress);
        gmx = IERC20(router.gmx());

        _name = string.concat(
            "VaultCraft ",
            IERC20Metadata(address(gmx)).name(),
            " Adapter"
        );
        _symbol = string.concat(
            "vcGmx-",
            IERC20Metadata(address(gmx)).symbol()
        );

        gmx.approve(
            address(router),
            type(uint256).max
        );

        gmx.approve(
            router.stakedGmxTracker(),
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
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit into LIDO pool
    function _protocolDeposit(uint256 assets, uint256) internal override {
        router.stakeGmx(assets);
    }

    /// @notice Withdraw from LIDO pool
    function _protocolWithdraw(
        uint256 assets,
        uint256 shares
    ) internal override {
        router.unstakeGmx(assets);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/
    function _totalAssets() internal view override returns (uint256) {
        return IRewardTracker(router.stakedGmxTracker()).stakedAmounts(address(this));
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
                IRewardTracker(router.stakedGmxTracker()).stakedAmounts(address(this)),
                supply,
                Math.Rounding.Up
            );
    }
}
