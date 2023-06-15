// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {StargateLpStakingAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IStargateStaking} from "../../../../../src/vault/adapter/stargate/lpStaking/StargateLpStakingAdapter.sol";
import {CurveStargateCompounder, CurveRoute} from "../../../../../src/vault/strategy/compounder/curve/CurveStargateCompounder.sol";
import {CurveCompounder} from "../../../../../src/vault/strategy/compounder/curve/CurveCompounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract CurveStargateCompounderTest is Test {
    IStargateStaking stargateStaking =
        IStargateStaking(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address stg = address(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address asset = address(0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56);
    address pool = address(0x3211C6cBeF1429da3D0d58494938299C92Ad5860);
    address router = address(0x99a58482BD75cbab83b27EC03CA68fF489b5788f);
    address stargateRouter =
        address(0x8731d54E9D02c286767d56ac03e8037C07e01e98);

    StargateLpStakingAdapter adapter;

    bytes4[8] sigs;

    address[9] toBaseAssetRoute;
    uint256[3][4] swapParams;

    CurveRoute[] curveRoutes;

    uint256[] minTradeAmounts;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 16946752);
        vm.selectFork(forkId);

        CurveRoute memory toAssetStruct = CurveRoute({
            route: toBaseAssetRoute,
            swapParams: swapParams
        });

        toBaseAssetRoute = [
            stg,
            pool,
            usdc,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        swapParams[0] = [uint256(0), 1, 3];
        curveRoutes.push(
            CurveRoute({route: toBaseAssetRoute, swapParams: swapParams})
        );
        minTradeAmounts.push(uint256(1e18));

        bytes memory stratData = abi.encode(
            usdc,
            router,
            curveRoutes,
            toAssetStruct,
            minTradeAmounts,
            abi.encode(stargateRouter)
        );

        address impl = address(new StargateLpStakingAdapter());
        adapter = StargateLpStakingAdapter(Clones.clone(impl));

        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new CurveStargateCompounder(),
                0,
                sigs,
                stratData
            ),
            address(stargateStaking),
            abi.encode(0)
        );

        // we deposit the initial funds so that the adapter actually holds some assets.
        // We also increase the block timestamp so that `harvest()` is executed when we
        // call it in one of the tests.
        deal(asset, address(this), 10000e6);
        IERC20(asset).approve(address(adapter), type(uint256).max);
        adapter.deposit(10000e6, address(this));
        vm.warp(block.timestamp + 12);
    }

    function test__init() public {
        assertEq(
            IERC20(stg).allowance(address(adapter), address(router)),
            type(uint256).max
        );
        assertEq(
            IERC20(usdc).allowance(address(adapter), address(stargateRouter)),
            type(uint256).max
        );
    }

    function test__compound() public {
        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 150_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__min_trade_amount() public {
        // the strategy should only compound if its balance > minTradeAmount
        deal(stg, address(adapter), 1e17);
        adapter.harvest();

        assertGt(IERC20(stg).balanceOf(address(adapter)), 0, "shouldn't trade if minAmount > balance");
    }

    function test__should_trade_whole_balance() public {
        // when trading, it should use all the available funds
        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 120_000);

        adapter.harvest();

        assertEq(IERC20(stg).balanceOf(address(this)), 0, "should trade whole balance");
    }

    function test__should_hold_no_tokens() public {
        // after trading, the adapter shouldn't hold any additional assets.
        // The funds it got from the trade should be deposited.
        // so oldBalance = newBalance for the underlying asset
        uint oldBal = IERC20(asset).balanceOf(address(adapter));

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 120_000);

        adapter.harvest();

        uint newBal = IERC20(asset).balanceOf(address(adapter));
        assertEq(oldBal, newBal, "shouldn't hold any assets in adapter");
    }

    function test__init_only_allow_asset() public {
        // token that we trade to MUST be the base asset used to get the adapter's asset.
        // In this case it would be USDC but we swap to asset (Stargate LP token)
        toBaseAssetRoute[2] = asset;
        curveRoutes[0] = CurveRoute({route: toBaseAssetRoute, swapParams: swapParams});
        CurveRoute memory toAssetStruct = CurveRoute({
            route: toBaseAssetRoute,
            swapParams: swapParams
        });

        bytes memory stratData = abi.encode(
            usdc,
            router,
            curveRoutes,
            toAssetStruct,
            minTradeAmounts,
            abi.encode(stargateRouter)
        );
        address impl = address(new StargateLpStakingAdapter());
        StargateLpStakingAdapter _adapter = StargateLpStakingAdapter(Clones.clone(impl));

        // need to do this before the call to initalize because expectRevert
        // would try to catch this call otherwise
        CurveStargateCompounder compounder = new CurveStargateCompounder();
        vm.expectRevert(CurveCompounder.InvalidConfig.selector);
        _adapter.initialize(
            abi.encode(
                asset,
                address(this),
                compounder,
                0,
                sigs,
                stratData
            ),
            address(stargateStaking),
            abi.encode(0)
        );
    }

    function test__no_rewards_available() public {
        uint totalAssets = adapter.totalAssets();

        adapter.harvest();

        assertEq(totalAssets, adapter.totalAssets(), "totalAssets shouldn't change if there are no reward tokens");
    }

}
