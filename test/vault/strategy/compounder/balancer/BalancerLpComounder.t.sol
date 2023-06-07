// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {BalancerGaugeAdapter, SafeERC20, IERC20, IERC20Metadata, Math, IGauge, IStrategy} from "../../../../../src/vault/adapter/balancer/BalancerGaugeAdapter.sol";
import {BalancerLpCompounder, BalancerUtils, IBalancerVault, BatchSwapStruct, SwapKind, FundManagement} from "../../../../../src/vault/strategy/compounder/balancer/BalancerLpCompounder.sol";
import {Clones} from "openzeppelin-contracts/proxy/Clones.sol";
import {MockStrategyClaimer} from "../../../../utils/mocks/MockStrategyClaimer.sol";

contract BalancerLpCompounderTest is Test {
    address _vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address _baseAsset = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 _poolId =
        0x3a4c6d2404b5eb14915041e01f63200a82f4a343000200000000000000000065;
    address _gauge = address(0xcf9f895296F5e1D66a7D4dcf1d92e1B435E9f999);

    BalancerGaugeAdapter adapter;

    address asset;
    address baseAsset;
    address bal;
    SwapKind swapKind = SwapKind.GIVEN_IN;

    bytes4[8] sigs;
    BatchSwapStruct[][] toBaseAssetPaths;
    FundManagement funds;
    address[] tokens;
    uint256[] minTradeAmounts;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.selectFork(forkId);

        IGauge gauge = IGauge(_gauge);
        asset = gauge.lp_token();
        bal = gauge.bal_token();

        toBaseAssetPaths.push();
        toBaseAssetPaths[0].push(BatchSwapStruct(_poolId, 0, 1));
        funds = FundManagement(
            address(this),
            false,
            payable(address(this)),
            false
        );

        minTradeAmounts.push(uint256(1));

        bytes memory stratData = abi.encode(
            asset,
            baseAsset,
            _vault,
            _poolId,
            swapKind,
            toBaseAssetPaths,
            funds,
            tokens,
            abi.encode("")
        );

        address impl = address(new BalancerGaugeAdapter());

        adapter = BalancerGaugeAdapter(Clones.clone(impl));

        adapter.initialize(
            abi.encode(
                asset,
                address(this),
                new BalancerLpCompounder(),
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
            IERC20(address(baseAsset)).allowance(
                address(adapter),
                address(_vault)
            ),
            type(uint256).max
        );

        assertEq(
            IERC20(address(asset)).allowance(address(adapter), address(_gauge)),
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
