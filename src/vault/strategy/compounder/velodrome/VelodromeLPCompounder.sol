// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {ERC4626Upgradeable as ERC4626, ERC20Upgradeable as ERC20, IERC20Upgradeable as IERC20} from "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {VelodromeCompounder, IAdapter, IWithRewards, IVelodromeRouter, VelodromeUtils} from "./VelodromeCompounder.sol";

contract VelodromeLpCompounder is VelodromeCompounder {
    function _verifyAsset(
        address baseAsset,
        address asset,
        bytes[] memory toAssetRoute,
        bytes memory optionalData
    ) internal override {
        (address pool, uint256 assetIndex) = abi.decode(
            optionalData,
            (address, uint256)
        );

        // Verify base asset to asset path
        if (toAssetRoute.route[0] != baseAsset) revert InvalidConfig();

        // Loop through the route until there are no more token or the array is over
        uint8 i = 1;
        while (i < 9) {
            if (i == 8 || toAssetRoute.route[i + 1] == address(0)) break;
            i++;
        }
        if (toAssetRoute.route[i] != asset) revert InvalidConfig();
    }
}
