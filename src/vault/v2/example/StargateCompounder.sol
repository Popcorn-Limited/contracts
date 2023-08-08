// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {StargateAdapter} from ".StargateAdapter.sol";
import {CurveCompounder} from ".CurveCompounder.sol";

contract StargateCompounder is StargateAdapter, CurveCompounder {
    function __StargateCompounder_init(
        IERC20 _underlying,
        IERC20 _lpToken,
        address _vault,
        bool _useLpToken,
        bool _autoHarvest,
        bytes memory _harvestData
    ) internal onlyInitializing {
        __StargateAdapter_init(_underlying, _lpToken, _vault, _useLpToken);
        __CurveCompounder_init(_autoHarvest, _harvestData);
    }
}
