// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BaseStrategy} from "./BaseStrategy.sol";

contract BaseCompounder is BaseStrategy {
    function __BaseCompounder_init(
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

    /**
     * @notice Claims rewards & executes the strategy
     */
    function harvest(bytes memory optionalData) external view virtual override {
        _harvest(optionalData);
    }

    /**
     * @notice Claims rewards & executes the strategy
     */
    function _harvest(
        bytes memory optionalData
    ) internal view virtual override {
        _compound();
    }

    function _compound() internal {
        _claimRewards();
        _swapToBaseAsset();

        if (IERC20(baseAsset).balanceOf(address(this)) == 0) {
            return;
        }

        _getAsset();

        useStrategyLpToken ? _depositLP(amount) : _depositUnderlying(amount);
    }

    function _swapToBaseAsset() internal virtual {}

    function _getAsset() internal virtual {}
}
