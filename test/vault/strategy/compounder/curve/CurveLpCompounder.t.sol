// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {ConvexAdapter, IConvexBooster, IConvexRewards, SafeERC20, IERC20, IERC20Metadata, Math} from "../../../../../src/vault/adapter/convex/ConvexAdapter.sol";
import {CurveLpCompounder, CurveRoute} from "../../../../../src/vault/strategy/compounder/curve/CurveLpCompounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract CurveLpCompounderTest is Test {
    IConvexBooster convexBooster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address stg = address(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address asset = address(0x9de1c3D446237ab9BaFF74127eb4F303802a2683);
    address pool = address(0x867fe27FC2462cff8890B54DfD64E6d42a9D1aC8);
    address router = address(0x99a58482BD75cbab83b27EC03CA68fF489b5788f);

    ConvexAdapter adapter;

    bytes4[8] sigs;

    address[9] toBaseAssetRoute;
    uint256[3][4] swapParams;

    CurveRoute[] curveRoutes;

    uint256[] minTradeAmounts;

    IConvexRewards convexRewards;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        (address _asset, , , address _convexRewards, , ) = convexBooster
            .poolInfo(150);

        convexRewards = IConvexRewards(_convexRewards);

        toBaseAssetRoute = [
            crv,
            0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, // crv / eth
            eth,
            0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2
            usdt,
            0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3crv
            usdc,
            address(0),
            address(0)
        ];
        swapParams[0] = [uint256(1), 0, 3];
        swapParams[1] = [uint256(2), 0, 3];
        swapParams[2] = [uint256(2), 1, 1];

        curveRoutes.push(
            CurveRoute({route: toBaseAssetRoute, swapParams: swapParams})
        );
        minTradeAmounts.push(uint256(0));

        toBaseAssetRoute = [
            cvx,
            0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, // cvx / eth
            eth,
            0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2
            usdt,
            0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3crv
            usdc,
            address(0),
            address(0)
        ];
        swapParams[0] = [uint256(1), 0, 3];
        swapParams[1] = [uint256(2), 0, 3];
        swapParams[2] = [uint256(2), 1, 1];

        curveRoutes.push(
            CurveRoute({route: toBaseAssetRoute, swapParams: swapParams})
        );
        minTradeAmounts.push(uint256(0));

        toBaseAssetRoute = [
            usdc,
            0x3211C6cBeF1429da3D0d58494938299C92Ad5860, // stg / usdc
            stg,
            pool,
            asset,
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        swapParams[0] = [uint256(1), 0, 3];
        swapParams[1] = [uint256(0), 0, 7];

        bytes memory stratData = abi.encode(
            usdc,
            router,
            curveRoutes,
            CurveRoute({route: toBaseAssetRoute, swapParams: swapParams}),
            minTradeAmounts,
            abi.encode(pool, 1)
        );

        address impl = address(new ConvexAdapter());
        adapter = ConvexAdapter(Clones.clone(impl));

        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new CurveLpCompounder(),
                0,
                sigs,
                stratData
            ),
            address(convexBooster),
            abi.encode(uint256(150))
        );
    }

    function test__init() public {
        assertEq(
            IERC20(crv).allowance(address(adapter), address(router)),
            type(uint256).max,
            "crv"
        );
        assertEq(
            IERC20(cvx).allowance(address(adapter), address(router)),
            type(uint256).max,
            "cvx"
        );
        assertEq(
            IERC20(usdc).allowance(address(adapter), address(router)),
            type(uint256).max,
            "usdc"
        );
    }

    function test__compound() public {
        deal(asset, address(this), 10000e18);
        IERC20(asset).approve(address(adapter), type(uint256).max);
        adapter.deposit(10000e18, address(this));

        uint256 oldTa = adapter.totalAssets();

        vm.warp(block.timestamp + 30 days);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }
}
