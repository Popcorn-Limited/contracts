// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {StargateLpStakingAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IStargateStaking} from "../../../../../src/vault/adapter/stargate/lpStaking/StargateLpStakingAdapter.sol";
import {UniV3StargateCompounder} from "../../../../../src/vault/strategy/compounder/UniV3StargateCompounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract UniV3StargateCompounderTest is Test {
    IStargateStaking stargateStaking =
        IStargateStaking(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address stg = address(0);
    address asset = address(0);
    address router = address(0);
    address stargateRouter = address(0);

    StargateLpStakingAdapter adapter;

    bytes4[8] sigs;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet", 16946752));
        vm.selectFork(forkId);

        address impl = address(new StargateLpStakingAdapter());
        adapter = StargateLpStakingAdapter(Clones.clone(impl));
        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new UniV3StargateCompounder(),
                0,
                sigs,
                abi.encode(
                    usdc,
                    router,
                    abi.encodePacked(stg, 3000, usdc),
                    "",
                    [0],
                    abi.encode(stargateRouter)
                )
            ),
            address(stargateStaking),
            abi.encode(0)
        );
    }

    function test__init() public {}

    function test__compound() public {
        deal(asset, address(this), 1e6);
        IERC20(asset).approve(address(adapter), type(uint256).max);
        adapter.deposit(1e6);

        vm.warp(block.timestamp + 14 days);

        adapter.harvest();

        emit log_uint(adapter.totalAssets());
    }
}
