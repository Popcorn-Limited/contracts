// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {CurveGaugeSingleAssetCompounder, CurveSwap} from "../src/vault/adapter/curve/gauge/other/CurveGaugeSingleAssetCompounder.sol";

contract SetHarvestValues is Script {
    address deployer;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address arb = 0x912CE59144191C1204E64559FE8253a0e49E6548;

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = arb;
        uint256[] memory minTradeAmounts = new uint256[](1);
        minTradeAmounts[0] = 0;

        CurveSwap[] memory swaps = new CurveSwap[](3);
        uint256[5][5] memory swapParams; // [i, j, swap type, pool_type, n_coins]
        address[5] memory pools;

        // arb->crvUSD->lp swap
        address[11] memory rewardRoute = [
            arb, // arb
            0x845C8bc94610807fCbaB5dd2bc7aC9DAbaFf3c55, // arb / crvUSD pool
            0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5, // crvUSD
            0x2FE7AE43591E534C256A1594D326e5779E302Ff4,
            0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // arb->crvUSD->lp swap params
        swapParams[0] = [uint256(1), 0, 2, 0, 0]; // arbIndex, crvUsdIndex, exchange_underlying, irrelevant, irrelevant
        swapParams[1] = [uint256(0), 1, 1, 1, 0]; // crvUsdIndex, irrelevant, exchange, stable, irrelevant

        swaps[0] = CurveSwap(rewardRoute, swapParams, pools);
        minTradeAmounts[0] = uint256(5e18);

        CurveGaugeSingleAssetCompounder(
            0x323053A0902E67791c06F65A5D2097ee79dD740F
        ).setHarvestValues(
                0xF0d4c12A5768D806021F80a262B4d39d26C58b8D, // curve router
                rewardTokens,
                minTradeAmounts,
                swaps
            );

        vm.stopBroadcast();
    }
}
