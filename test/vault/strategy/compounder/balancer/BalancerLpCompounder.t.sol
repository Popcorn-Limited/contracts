// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {BalancerGaugeAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, IStrategy} from "../../../../../src/vault/adapter/balancer/BalancerGaugeAdapter.sol";
import {BalancerLpCompounder, IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest, BalancerRoute} from "../../../../../src/vault/strategy/compounder/balancer/BalancerLpCompounder.sol";

contract BalancerLpCompounderTest is Test {
    address vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address baseAsset = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    bytes32 poolId =
        0xe7e2c68d3b13d905bbb636709cf4dfd21076b9d20000000000000000000005ca;
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    bytes32 balWethPoolId =
        0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;

    BalancerGaugeAdapter adapter;

    address asset;
    address bal;

    bytes4[8] sigs;

    BalancerRoute toAssetRoute;
    uint256[] minTradeAmounts;

    BatchSwapStep[] swaps;
    IAsset[] assets;
    int256[] limits;

    uint256[] amounts;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        address impl = address(new BalancerGaugeAdapter());

        adapter = BalancerGaugeAdapter(Clones.clone(impl));

        IGauge gauge = IGauge(
            address(0xee01c0d9c0439c94D314a6ecAE0490989750746C)
        );
        asset = gauge.lp_token();
        bal = address(0xba100000625a3754423978a60c9317c58a424e3D);

        vm.label(address(asset), "asset");

        swaps.push(BatchSwapStep(balWethPoolId, 0, 1, 0, "")); // trade BAL for WETH
        assets.push(IAsset(bal));
        assets.push(IAsset(weth));
        limits.push(type(int256).max); // Bal limit
        limits.push(-1); // WETH limit

        BalancerRoute[] memory toBaseAssetRoutes = new BalancerRoute[](1);
        toBaseAssetRoutes[0] = BalancerRoute(swaps, assets, limits);

        minTradeAmounts.push(uint256(0));

        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new BalancerLpCompounder(),
                0,
                sigs,
                abi.encode(
                    baseAsset,
                    vault,
                    toBaseAssetRoutes,
                    BalancerRoute(
                        new BatchSwapStep[](0),
                        new IAsset[](0),
                        new int256[](0)
                    ),
                    minTradeAmounts,
                    abi.encode(poolId, 0, 2)
                )
            ),
            address(0x239e55F427D44C3cc793f49bFB507ebe76638a2b),
            abi.encode(address(gauge))
        );
    }

    function test__init() public {
        assertEq(
            IERC20(address(baseAsset)).allowance(
                address(adapter),
                address(vault)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(bal).allowance(address(adapter), address(vault)),
            type(uint256).max
        );

        (
            address baseAsset,
            address vault,
            BalancerRoute[] memory toBaseAssetRoutes,
            BalancerRoute memory toAssetRoute,
            uint256[] memory minTradeAmounts,
            bytes memory optionalData
        ) = abi.decode(
                adapter.strategyConfig(),
                (
                    address,
                    address,
                    BalancerRoute[],
                    BalancerRoute,
                    uint256[],
                    bytes
                )
            );
    }

    function test__compound() public {
        deal(address(asset), address(this), 10e18);
        IERC20(address(asset)).approve(address(adapter), type(uint256).max);
        adapter.deposit(10e18, address(this));

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 1000_000);
        vm.warp(block.timestamp + 15000_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__compound_zero_rewards() public {
        deal(address(asset), address(this), 1e18);
        IERC20(address(asset)).approve(address(adapter), type(uint256).max);
        adapter.deposit(1e18, address(this));

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 150);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__should_trade_whole_balance() public {
        // when trading, it should use all the available funds
        vm.roll(block.number + 1000_000);
        vm.warp(block.timestamp + 15000_000);

        adapter.harvest();

        assertEq(
            IERC20(bal).balanceOf(address(this)),
            0,
            "should trade whole balance"
        );
    }

    function test__should_hold_no_tokens() public {
        // after trading, the adapter shouldn't hold any additional assets.
        // The funds it got from the trade should be deposited.
        // so oldBalance = newBalance for the underlying asset
        uint oldBal = IERC20(asset).balanceOf(address(adapter));

        vm.roll(block.number + 1000_000);
        vm.warp(block.timestamp + 15000_000);

        adapter.harvest();

        uint newBal = IERC20(asset).balanceOf(address(adapter));
        assertEq(oldBal, newBal, "shouldn't hold any assets in adapter");
    }

    function test__claim() public {
        address bob = address(0x2e234DAe75C793f67A35089C9d99245E1C58470b);

        deal(address(asset), address(this), 1e18);
        IERC20(address(asset)).approve(address(adapter), type(uint256).max);
        adapter.deposit(1e18, address(this));

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 150_000);

        vm.prank(bob);

        adapter.claim();

        assertGt(IERC20(bal).balanceOf(address(adapter)), 0);
    }
}
