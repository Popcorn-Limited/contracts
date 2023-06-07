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
    address _baseAsset = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    bytes32 _poolId =
        0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd;
    address _gauge = address(0xcf9f895296F5e1D66a7D4dcf1d92e1B435E9f999);
    address _psuedoMinter = address(0xc3ccacE87f6d3A81724075ADcb5ddd85a8A1bB68);

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
            _baseAsset,
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
            address(0xc3ccacE87f6d3A81724075ADcb5ddd85a8A1bB68),
            abi.encode(address(gauge))
        );
    }

    function test__init() public {
        assertEq(
            IERC20(address(_baseAsset)).allowance(
                address(adapter),
                address(_vault)
            ),
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
