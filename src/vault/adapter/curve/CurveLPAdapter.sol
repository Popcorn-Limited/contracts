// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {AdapterBase, IERC20, IERC20Metadata, SafeERC20, ERC20, Math, IAdapter} from "../abstracts/AdapterBase.sol";
import {IPool, IMetaRegistry } from "./ICurve.sol";

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


    function initialize(
        bytes memory adapterInitData,
        address _registry,
        bytes memory curveInitData
    ) external initializer {
        __AdapterBase_init(adapterInitData);
        
        (uint poolId) = abi.decode(curveInitData, (uint));
        IMetaRegistry registry = IMetaRegistry(_registry);
        // save to memory since we'll read this value multiple times
        address _pool = registry.pool_list(poolId);
        pool = IPool(_pool);
        poolToken = IERC20(registry.get_lp_token(_pool));
        numberOfTokens = registry.get_n_coins(_pool);

        address[8] memory coins = registry.get_coins(_pool);
        // cache to save gas
        address _asset = asset();
        for (uint i; i < coins.length; ){
            if (coins[i] == _asset){
                tokenIndex = int128(int(i));
                break;
            }
            unchecked {++i;}
        }

        // `coins()` uses uint256 instead of int128 like the other function for the token index
        require(pool.coins(uint(uint128(tokenIndex))) == asset(), "asset doesn't match pool token at given index");

        // TODO: name it properly
        _name = string.concat(
            "VaultCraft Curve LP"
        );
        _symbol = "vcCrvLP";
    
        IERC20(asset()).approve(_pool, type(uint).max);
    }

    function _protocolDeposit(uint amount, uint) internal override {
        // uint[] memory amounts = new uint[](numberOfTokens);
        // amounts[uint(uint128(tokenIndex))] = amount;
        uint[3] memory amounts = [0, amount, 0];
        pool.add_liquidity(amounts, 0);
    }

    function _protocolWithdraw(uint, uint shares) internal override {
        uint underlyingShares = convertToUnderlyingShares(0, shares);
        pool.remove_liquidity_one_coin(underlyingShares, tokenIndex, 0);
    }

    function _totalAssets() internal view override returns (uint) {
        uint lpBalance = poolToken.balanceOf(address(this));
        // `calc_withdraw_one_coin()` reverts if called with `0` for the token amount
        return lpBalance == 0 ? 0 : pool.calc_withdraw_one_coin(lpBalance, tokenIndex);
    }
    

    function convertToUnderlyingShares(
        uint,
        uint shares
    ) public view override returns (uint) {
        uint supply = totalSupply();
        return supply == 0 ? shares : shares.mulDiv(poolToken.balanceOf(address(this)), supply, Math.Rounding.Down);
    }
}