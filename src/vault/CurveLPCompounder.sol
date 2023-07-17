pragma solidity ^0.8.15;

import {VaultWithStrategy} from "./VaultWithStrategy.sol";
import {BaseVaultInitData} from "./BaseVault.sol";
import {IGauge, IMinter} from "./adapter/curve/ICurve.sol";
import {ICurveRouter} from "../interfaces/external/curve/ICurveRouter.sol";
import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/interfaces/IERC20Metadata.sol";

struct CurveRoute {
    address[9] route;
    uint256[3][4] swapParams;
}

struct StrategyConfig {
    uint256 autoHarvest;
    uint256 harvestCooldown;
    address router;
    address baseAsset;
    CurveRoute[] toBaseAssetRoutes;
    uint256[] minTradeAmounts;
    IPool pool;
    uint baseAssetIndex; // the index is used in add_liquidity
}

interface IPool {
    // TODO: add remaining functions for different number of coins
    function add_liquidity(uint[3] memory amounts, uint minOut) external;
}

contract CurveLPCompounder is VaultWithStrategy {
    IGauge gauge;
    IMinter public minter;
    address crv;

    address router;
    address baseAsset;
    CurveRoute[] toBaseAssetRoutes;
    uint256[] minTradeAmounts;
    IPool pool;
    uint baseAssetIndex;

    /// @dev number of tokens in the curve pool
    uint internal numberOfTokens;

    constructor() {
        _disableInitializers();
    }

    function initialize(BaseVaultInitData calldata baseVaultInitData, bytes calldata initData) external initializer {
        // TODO: can we force the user to send BaseVaultInitData separately through the calldata?
        // The struct is the same for all the vaults. We shouldn't need to encode it
        (
            address _gauge,
            address _minter,
            StrategyConfig memory _stratConfig
        ) = abi.decode(
            initData, (address, address, StrategyConfig)
        );
        __VaultWithStrategy__init(baseVaultInitData, _stratConfig.autoHarvest, _stratConfig.harvestCooldown);
        
        gauge = IGauge(_gauge);
        minter = IMinter(_minter);
        crv = minter.token();
        
        router = _stratConfig.router;
        baseAsset = _stratConfig.baseAsset;
        /// @dev assigning `toBaseAssetRoutes = _stratConfig.toBaseAssetRoutes` doesn't work.
        // we have to manually assign each index
        for (uint i; i < _stratConfig.toBaseAssetRoutes.length;) {
            toBaseAssetRoutes.push(_stratConfig.toBaseAssetRoutes[i]);
            unchecked {
                ++i;
            }
        }
        minTradeAmounts = _stratConfig.minTradeAmounts;
        pool = _stratConfig.pool;
        baseAssetIndex = _stratConfig.baseAssetIndex;

        IERC20(baseVaultInitData.asset).approve(_gauge, type(uint).max);

        IERC20(_stratConfig.baseAsset).approve(address(_stratConfig.pool), type(uint).max);

        address[] memory tokens = rewardTokens();
        uint length = tokens.length;
        for (uint i; i < length;) {
            IERC20(tokens[i]).approve(_stratConfig.router, type(uint).max);
            unchecked {
                ++i;
            }
        }
    }


    function harvest() public override {
        lastHarvest = block.timestamp;

        // cache for gas savings
        IERC20 _asset = IERC20(asset());

        uint balBefore = _asset.balanceOf(address(this));
        
        minter.mint(address(gauge));
        _swapToBaseAsset();

        if (IERC20(baseAsset).balanceOf(address(this)) == 0) {
            emit Harvest();
            return;
        }

        _getAsset();

        strategyDeposit(_asset.balanceOf(address(this)) - balBefore, 0);
    }

    function rewardTokens() public view override returns (address[] memory) {
        uint256 rewardCount = gauge.reward_count();
        address[] memory _rewardTokens = new address[](rewardCount + 1);
        _rewardTokens[0] = crv;
        for (uint256 i; i < rewardCount; ++i) {
            _rewardTokens[i + 1] = gauge.reward_tokens(i);
        }
        return _rewardTokens;
    }

    function _swapToBaseAsset()
        internal
    {
        // Trade rewards for base asset
        address[] memory tokens = rewardTokens();
        uint256 len = tokens.length;
        for (uint256 i; i < len;) {
            uint256 rewardBal = IERC20(tokens[i]).balanceOf(address(this));
            if (rewardBal >= minTradeAmounts[i]) {
                ICurveRouter(router).exchange_multiple(
                    toBaseAssetRoutes[i].route, toBaseAssetRoutes[i].swapParams, rewardBal, 0
                );
            }
            unchecked {
                ++i;
            }
        }
    }

    function _getAsset()
        internal
        virtual
    {
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
        uint _numberOfTokens = numberOfTokens;

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

    function _protocolDeposit(uint amount, uint) internal override {
        gauge.deposit(amount);
    }

    function _protocolWithdraw(uint amount, uint) internal override {
        gauge.withdraw(amount);
    }

    function _totalAssets() internal view override returns (uint) {
        return gauge.balanceOf(address(this));
    }
}
