// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";
import {CurveGaugeCompounder, CurveSwap} from "../src/vault/adapter/curve/gauge/mainnet/CurveGaugeCompounder.sol";

contract SetHarvestValues is Script {
    address deployer;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = crv;
        uint256[] memory minTradeAmounts = new uint256[](1);
        minTradeAmounts[0] = 10e18;

        CurveSwap[] memory swaps = new CurveSwap[](1);
        uint256[5][5] memory swapParams; // [i, j, swap type, pool_type, n_coins]
        address[5] memory pools;

        int128 indexIn = int128(1); // WETH index

        // arb->crvUSD->lp swap
        address[11] memory rewardRoute = [
            crv, // crv
            0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, // triCRV pool
            0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E, // crvUSD
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // arb->crvUSD->lp swap params
        swapParams[0] = [uint256(2), 0, 1, 0, 0]; // crvIndex, wethIndex, exchange, irrelevant, irrelevant

        swaps[0] = CurveSwap(rewardRoute, swapParams, pools);

        CurveGaugeCompounder(0xdce45fEab60668195D891242914864837Aa22d8d)
            .setHarvestValues(
                0xF0d4c12A5768D806021F80a262B4d39d26C58b8D, // curve router
                rewardTokens,
                minTradeAmounts,
                swaps,
                indexIn
            );

        vm.stopBroadcast();
    }
}
