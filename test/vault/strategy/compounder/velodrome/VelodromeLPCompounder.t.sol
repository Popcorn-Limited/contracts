// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {VelodromeAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, ILpToken} from "../../../../../src/vault/adapter/velodrome/VelodromeAdapter.sol";
import {VelodromeLpCompounder, VelodromeUtils, route} from "../../../../../src/vault/strategy/compounder/velodrome/VelodromeLpCompounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract VelodromeLpCompounderTest is Test {
    address _gauge = address(0x2f733b00127449fcF8B5a195bC51Abb73B7F7A75);
    address router = address(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);
    address op = address(0x4200000000000000000000000000000000000042);

    VelodromeAdapter adapter;

    IGauge gauge;
    ILpToken lpToken;
    address lpToken0;
    address lpToken1;
    address velo;
    address asset;

    bytes4[8] sigs;
    route[][] toBaseAssetPaths;
    route[][] toAssetPaths;
    uint256[] minTradeAmounts;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.selectFork(forkId);

        IGauge gauge = IGauge(_gauge);
        asset = gauge.stake();
        lpToken = ILpToken(asset);
        velo = gauge.rewards(2);
        lpToken0 = lpToken.token0();
        lpToken1 = lpToken.token1();

        toBaseAssetPaths.push();
        toBaseAssetPaths[0].push(route(velo, lpToken1, false));

        toAssetPaths.push();
        toAssetPaths[0].push(route(lpToken1, lpToken0, false));

        minTradeAmounts.push(uint256(1));

        bytes memory stratData = abi.encode(
            op,
            router,
            toBaseAssetPaths,
            toAssetPaths,
            minTradeAmounts,
            abi.encode("")
        );

        address impl = address(new VelodromeAdapter());

        adapter = VelodromeAdapter(Clones.clone(impl));

        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new VelodromeLpCompounder(),
                0,
                sigs,
                stratData
            ),
            address(gauge),
            abi.encode(address(gauge))
        );
    }

    function test__init() public {
        assertEq(
            IERC20(address(lpToken0)).allowance(
                address(adapter),
                address(router)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(address(lpToken1)).allowance(
                address(adapter),
                address(router)
            ),
            type(uint256).max
        );
    }

    function test__compound() public {
        deal(address(lpToken), address(this), 1e18);
        IERC20(address(lpToken)).approve(address(adapter), type(uint256).max);
        adapter.deposit(1e18, address(this));

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 150_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }
}
