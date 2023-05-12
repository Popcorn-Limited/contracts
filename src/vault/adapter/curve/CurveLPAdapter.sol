// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IAdapter} from "../abstracts/AdapterBase.sol";
import {IPool, IMetaRegistry} from "./ICurve.sol";

contract CurveLPAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Math for uint256;

    string internal _name;
    string internal _symbol;

    /// @notice The Curve Pool contract
    IPool public pool;
    IERC20 public poolToken;

    // these two are private because they are not necessary to interact with the vault.
    // the number of coins in the pool
    uint private numberOfTokens;
    // the index of the coin which we deposit/withdraw
    int128 private tokenIndex;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    error AssetMismatch();

    function initialize(
        bytes memory adapterInitData,
        address _registry,
        bytes memory curveInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);

        IMetaRegistry registry = IMetaRegistry(_registry);

        uint poolId = abi.decode(curveInitData, (uint));
        // save to memory since we'll read this value multiple times
        address _pool = registry.pool_list(poolId);

        pool = IPool(_pool);
        poolToken = IERC20(registry.get_lp_token(_pool));
        numberOfTokens = registry.get_n_coins(_pool);

        address[8] memory coins = registry.get_coins(_pool);

        // cache to save gas
        address _asset = asset();
        for (uint i; i < coins.length; ) {
            if (coins[i] == _asset) {
                tokenIndex = int128(int(i));
                break;
            }
            unchecked {
                ++i;
            }
        }

        // `coins()` uses uint256 instead of int128 like the other function for the token index
        if (pool.coins(uint(uint128(tokenIndex))) != asset())
            revert AssetMismatch();

        _name = string.concat(
            "VaultCraft Curve Lp ",
            IERC20Metadata(_asset).name(),
            " Adapter"
        );
        _symbol = string.concat("vcCrvLp-", IERC20Metadata(_asset).symbol());

        IERC20(asset()).approve(_pool, type(uint).max);
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

    function _totalAssets() internal view override returns (uint) {
        uint lpBalance = poolToken.balanceOf(address(this));
        // `calc_withdraw_one_coin()` reverts if called with `0` for the token amount
        return
            lpBalance == 0
                ? 0
                : pool.calc_withdraw_one_coin(lpBalance, tokenIndex);
    }

    function convertToUnderlyingShares(
        uint,
        uint shares
    ) public view override returns (uint) {
        uint supply = totalSupply();
        return
            supply == 0
                ? shares
                : shares.mulDiv(
                    poolToken.balanceOf(address(this)),
                    supply,
                    Math.Rounding.Down
                );
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _protocolDeposit(uint amount, uint) internal override {
        // Curve's `add_liquidity` expects a fixed-size array as the first argument.
        // The size of the array depends on the pool.
        // For example, 3CRV has a size of 3 while stETH/ETH has 2.
        //
        // Since our adapter is supposed to be usable with all kinds of pools,
        // we can't use a fixed-size array here. Calling the function with an
        // unbounded one will revert. The reason is the way those two types of arrays
        // are encoded.
        // Fixed size arrays simply concatenate its values with each one taking up 32 bytes: 0, 1, 2
        // see https://github.com/willitscale/learning-solidity/blob/master/support/INVALID_IMPLICIT_CONVERSION_OF_ARRAYS.MD#211-memory-layout
        // Unbounded arrays do the same but add a 32 byte value at the beginning specifying its length:
        // 3, 0, 1, 2 see https://github.com/willitscale/learning-solidity/blob/master/support/INVALID_IMPLICIT_CONVERSION_OF_ARRAYS.MD#221-memory-layout
        //
        // By building the calldata ourselves, we can have a general solution.
        // That would be the "cleanest" one. But, it comes with hefty gas costs
        // since building the calldata is pretty expensive. For one, you can't slice
        // memory arrays right now. That's only supported for calldata. So you have to
        // build a custom loop and concat each value.
        // Because _protocolDeposit() is a user-facing function we should prioritize
        // gas usage more than code-quality
        //
        // Instead, we proceed with the "dumb" solution: a simple switch statement
        // We can't do `uint[numberOfTokens]` either. Has to be a constant/literal value

        // cache for gas savings
        uint _numberOfTokens = numberOfTokens;

        if (_numberOfTokens == 2) {
            uint[2] memory amounts = [uint(0), 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        } else if (_numberOfTokens == 3) {
            uint[3] memory amounts = [uint(0), 0, 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        } else if (_numberOfTokens == 4) {
            uint[4] memory amounts = [uint(0), 0, 0, 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        } else if (_numberOfTokens == 5) {
            uint[5] memory amounts = [uint(0), 0, 0, 0, 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        } else if (_numberOfTokens == 6) {
            uint[6] memory amounts = [uint(0), 0, 0, 0, 0, 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        } else if (_numberOfTokens == 7) {
            uint[7] memory amounts = [uint(0), 0, 0, 0, 0, 0, 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        } else if (_numberOfTokens == 8) {
            // 8 seems to be the max. amount of tokens in a pool
            uint[8] memory amounts = [uint(0), 0, 0, 0, 0, 0, 0, 0];
            amounts[uint(uint128(tokenIndex))] = amount;
            pool.add_liquidity(amounts, 0);
        }
    }

    function _protocolWithdraw(uint, uint shares) internal override {
        uint underlyingShares = convertToUnderlyingShares(0, shares);
        pool.remove_liquidity_one_coin(underlyingShares, tokenIndex, 0);
    }
}
