// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import {Test} from "forge-std/Test.sol";

contract Tester is Test {
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address stg = address(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address asset = address(0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56);

    address baseAsset;
    address router = address(0x99a58482BD75cbab83b27EC03CA68fF489b5788f);
    address[9][] toBaseAssetRoutes;
    address[9] toAssetRoute;
    uint256[3][4] swapParams;
    uint256[] minTradeAmounts;
    bytes optionalData;
    bytes data;

    function setUp() public {
        toBaseAssetRoutes.push(
            [
                stg,
                usdc,
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0)
            ]
        );
        minTradeAmounts.push(uint256(0));

        data = abi.encode(
            baseAsset,
            router,
            toBaseAssetRoutes,
            toAssetRoute,
            swapParams,
            minTradeAmounts,
            optionalData
        );
    }

    function test_stuff() public {
        (
            address baseAsset,
            address router,
            address[9][] memory toBaseAssetRoutes,
            address[9] memory toAssetRoute,
            uint256[3][4] memory swapParams,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    address[9][],
                    address[9],
                    uint256[3][4],
                    uint256[],
                    bytes
                )
            );
    }
}
