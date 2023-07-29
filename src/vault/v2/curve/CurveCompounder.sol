pragma solidity ^0.8.15;

import {IERC20} from "openzeppelin-contracts/interfaces/IERC20.sol";
import {BaseStrategy} from "../BaseStrategy.sol";
import {ICurveRouter} from "../../../interfaces/external/curve/ICurveRouter.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

struct CurveRoute {
    address[9] route;
    uint256[3][4] swapParams;
}



struct StrategyConfig {
    address router;
    uint128 harvestCooldown;
    address baseAsset;
    uint8 autoHarvest;
    CurveRoute[] toBaseAssetRoutes;
    uint256[] minTradeAmounts;
}

abstract contract CurveCompounder is BaseStrategy {

    address router;
    address baseAsset;
    CurveRoute[] toBaseAssetRoutes;
    uint256[] minTradeAmounts;

    function __CurveCompounder__init(StrategyConfig memory _stratConfig) internal onlyInitializing {
        __BaseStrategy__init(_stratConfig.harvestCooldown, _stratConfig.autoHarvest);

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


        address[] memory tokens = rewardTokens;
        uint length = tokens.length;
        for (uint i; i < length;) {
            IERC20(tokens[i]).approve(_stratConfig.router, type(uint).max);
            unchecked {
                ++i;
            }
        }
    }

    function harvest() public override {
        lastHarvest = uint128(block.timestamp);

        // cache for gas savings
        IERC20 _asset = IERC20(asset());

        uint balBefore = _asset.balanceOf(address(this));
        
        _claim();
        
        _swapToBaseAsset();

        if (IERC20(baseAsset).balanceOf(address(this)) == 0) {
            emit Harvest();
            return;
        }

        _getAsset();

        strategyDeposit(_asset.balanceOf(address(this)) - balBefore, 0);
    }


    function _swapToBaseAsset()
        internal
    {
        // Trade rewards for base asset
        address[] memory tokens = rewardTokens;
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

    function _getAsset() internal virtual;
}