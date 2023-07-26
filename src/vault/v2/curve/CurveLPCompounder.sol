pragma solidity ^0.8.15;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";

import {BaseVaultInitData} from "../BaseVault.sol";
import {CurveCompounder, StrategyConfig, CurveRoute} from "./CurveCompounder.sol";
import {CurveLP} from "./CurveLP.sol";

interface IPool {
    // TODO: add remaining functions for different number of coins
    function add_liquidity(uint[3] memory amounts, uint minOut) external;
}

contract CurveLPCompounder is CurveCompounder, CurveLP {

    IPool pool;
    uint8 internal numberOfTokens;
    uint baseAssetIndex; // the index is used in add_liquidity
    /// @dev number of tokens in the curve pool

    constructor() {
        _disableInitializers();
    }

    function initialize(BaseVaultInitData calldata baseVaultInitData, bytes calldata initData) external {
        (
            address _gauge,
            address _minter,
            address _pool,
            uint8 _numberOfTokens,
            uint _baseAssetIndex,
            StrategyConfig memory _stratConfig
        ) = abi.decode(
            initData, (address, address, address, uint8, uint, StrategyConfig)
        );

        __CurveCompounder__init(_stratConfig);
        __CurveLP__init(baseVaultInitData, _gauge, _minter, baseVaultInitData.asset);

        IERC20(baseAsset).approve(_pool, type(uint).max);
        pool = IPool(_pool);

        numberOfTokens = _numberOfTokens;
        baseAssetIndex = _baseAssetIndex;
    }

    /// @dev called by Strategy contract. We can't put this into the strategy contract since it doesn't
    /// know how to get from the reward tokens to the vault's asset.
    /// For example, the CurveLPCompounder needs to deposit token X into a Curve pool to receive the LP token (vault's asset).
    /// A different Vault would maybe trade the reward tokens directly for the vault's asset instead.
    /// To keep the strategy contract universal, we move the `_getAsset()` function into the vault contract.
    function _getAsset() internal override {
        // Curve's `add_liquidity` expects a fixed-size array as the first argument.
        // The size of the array depends on the pool.
        // For example, 3CRV has a size of 3 while stETH/ETH has 2.
        //
        // Since our vault is supposed to be usable with all kinds of pools,
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
        // Because harvest() is a user-facing function we should prioritize
        // gas usage more than code-quality
        //
        // Instead, we proceed with the "dumb" solution: a simple switch statement
        //
        // We can't do `uint[numberOfTokens]` either. Has to be a constant/literal value

        // cache for gas savings
        uint8 _numberOfTokens = numberOfTokens;

        uint amount = IERC20(baseAsset).balanceOf(address(this));

        // if (_numberOfTokens == 2) {
        //     uint[2] memory amounts = [uint(0), 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // } else if (_numberOfTokens == 3) {
        //     uint[3] memory amounts = [uint(0), 0, 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // } else if (_numberOfTokens == 4) {
        //     uint[4] memory amounts = [uint(0), 0, 0, 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // } else if (_numberOfTokens == 5) {
        //     uint[5] memory amounts = [uint(0), 0, 0, 0, 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // } else if (_numberOfTokens == 6) {
        //     uint[6] memory amounts = [uint(0), 0, 0, 0, 0, 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // } else if (_numberOfTokens == 7) {
        //     uint[7] memory amounts = [uint(0), 0, 0, 0, 0, 0, 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // } else if (_numberOfTokens == 8) {
        //     // 8 seems to be the max. amount of tokens in a pool
        //     uint[8] memory amounts = [uint(0), 0, 0, 0, 0, 0, 0, 0];
        //     amounts[baseAssetIndex] = amount;
        //     pool.add_liquidity(amounts, 0);
        // }
        
        uint[3] memory amounts = [uint(0), 0, 0];
        amounts[baseAssetIndex] = amount;
        pool.add_liquidity(amounts, 0);
    }
}