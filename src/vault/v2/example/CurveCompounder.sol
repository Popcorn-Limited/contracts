// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BaseStrategy} from "../base/BaseStrategy.sol";

contract CurveCompounder is BaseStrategy {
    function __CurveCompounder_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        address _vault,
        bool _useLpToken,
        bool _autoHarvest,
        bytes memory _harvestData
    ) internal onlyInitializing {
        __BaseStrategy_init(
            _underlying,
            _lpToken,
            _vault,
            _useLpToken,
            _autoHarvest,
            _harvestData
        );
    }

    function _swapToBaseAsset() internal override {
        // Trade rewards for base asset
        address[] memory tokens = rewardTokens();
        uint256 len = tokens.length;
        for (uint256 i; i < len; ) {
            uint256 rewardBal = IERC20(tokens[i]).balanceOf(address(this));
            if (rewardBal >= minTradeAmounts[i]) {
                ICurveRouter(router).exchange_multiple(
                    toBaseAssetRoutes[i].route,
                    toBaseAssetRoutes[i].swapParams,
                    rewardBal,
                    0
                );
            }
            unchecked {
                ++i;
            }
        }
    }
}
