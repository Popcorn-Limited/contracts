// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {StargateLpStakingAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IStargateStaking} from "../../../../../src/vault/adapter/stargate/lpStaking/StargateLpStakingAdapter.sol";
import {UniV3StargateCompounder, UniswapV3Utils} from "../../../../../src/vault/strategy/compounder/UniV3StargateCompounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";

contract UniV3StargateCompounderTest is Test {
    IStargateStaking stargateStaking =
        IStargateStaking(0xB0D502E938ed5f4df2E681fE6E419ff29631d62b);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address stg = address(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address asset = address(0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56);
    address router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564); // V2 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
    address stargateRouter =
        address(0x8731d54E9D02c286767d56ac03e8037C07e01e98);

    StargateLpStakingAdapter adapter;

    bytes4[8] sigs;
    bytes[] toBaseAssetPaths;
    uint256[] minTradeAmounts;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 16946752);
        vm.selectFork(forkId);

        toBaseAssetPaths.push(abi.encodePacked(stg, uint24(3000), usdc));
        minTradeAmounts.push(uint256(0));

        bytes memory stratData = abi.encode(
            usdc,
            router,
            toBaseAssetPaths,
            "",
            minTradeAmounts,
            abi.encode(stargateRouter)
        );

        emit log_bytes(stratData);

        address impl = address(new StargateLpStakingAdapter());
        adapter = StargateLpStakingAdapter(Clones.clone(impl));
        emit log_address(address(adapter));
        emit log_address(address(this));
        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new UniV3StargateCompounder(),
                0,
                sigs,
                stratData
            ),
            address(stargateStaking),
            abi.encode(0)
        );
    }

    function test__init() public {}

    function test__compound() public {
        deal(asset, address(this), 10000e6);
        IERC20(asset).approve(address(adapter), type(uint256).max);
        adapter.deposit(10000e6, address(this));

        vm.roll(block.number + 10_000);
        vm.warp(block.timestamp + 150_000);

        adapter.harvest();

        emit log_uint(adapter.totalAssets());
    }

    function test__uni() public {
        deal(stg, address(this), 100e18);
        IERC20(stg).approve(router, type(uint256).max);
        UniswapV3Utils.swapSingle(router, 100e18);
        emit log_uint(IERC20(usdc).balanceOf(address(this)));
    }
}
