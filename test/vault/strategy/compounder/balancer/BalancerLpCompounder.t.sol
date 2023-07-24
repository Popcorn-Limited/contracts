// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {BalancerGaugeAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, IStrategy} from "../../../../../src/vault/adapter/balancer/BalancerGaugeAdapter.sol";
import {BalancerLpCompounder, IBalancerVault, SwapKind, IAsset, BatchSwapStep, FundManagement, JoinPoolRequest, BalancerRoute} from "../../../../../src/vault/strategy/compounder/balancer/BalancerLpCompounder.sol";

// TODO - update test using the new BalancerLpCompounder

contract BalancerLpCompounderTest is Test {
    address vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address baseAsset = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    bytes32 poolId =
        0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd;
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    bytes32 balWethPoolId =
        0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;

    BalancerGaugeAdapter adapter;

    address asset;
    address bal;

    bytes4[8] sigs;

    BalancerRoute toAssetRoute;
    uint256[] minTradeAmounts;

    BatchSwapStep[] swaps;
    IAsset[] assets;
    int256[] limits;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        address impl = address(new BalancerGaugeAdapter());

        adapter = BalancerGaugeAdapter(Clones.clone(impl));

        IGauge gauge = IGauge(
            address(0xcf9f895296F5e1D66a7D4dcf1d92e1B435E9f999)
        );
        asset = gauge.lp_token();
        bal = gauge.bal_token();

        vm.label(address(asset), "asset");

        swaps.push(BatchSwapStep(balWethPoolId, 0, 1, 0, "")); // trade BAL for WETH
        assets.push(IAsset(bal));
        assets.push(IAsset(weth));
        limits.push(type(int256).max); // Bal limit
        limits.push(-1); // WETH limit

        BalancerRoute[] memory toBaseAssetRoutes = new BalancerRoute[](1);
        toBaseAssetRoutes[0] = BalancerRoute(swaps, assets, limits);

        minTradeAmounts.push(uint256(100));

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
                    abi.encode(poolId, 1)
                )
            ),
            address(0xc3ccacE87f6d3A81724075ADcb5ddd85a8A1bB68),
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
            IERC20(address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8))
                .allowance(address(adapter), address(vault)),
            type(uint256).max
        );
    }

    function test__compound() public {
        deal(address(asset), address(this), 1e18);
        IERC20(address(asset)).approve(address(adapter), type(uint256).max);
        adapter.deposit(1e18, address(this));

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 150_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__should_trade_whole_balance() public {
        // when trading, it should use all the available funds
        vm.warp(block.timestamp + 30 days);

        adapter.harvest();

        assertEq(IERC20(bal).balanceOf(address(this)), 0, "should trade whole balance");
    }

    function test__should_hold_no_tokens() public {
        // after trading, the adapter shouldn't hold any additional assets.
        // The funds it got from the trade should be deposited.
        // so oldBalance = newBalance for the underlying asset
        uint oldBal = IERC20(asset).balanceOf(address(adapter));

        vm.warp(block.timestamp + 30 days);

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
