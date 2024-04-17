// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {BalancerCompounder, SafeERC20, IERC20, IERC20Metadata, Math, HarvestValue, BatchSwapStep, IBalancerVault, IGauge, IStrategy, IAdapter, IWithRewards, IAsset, BatchSwapStep} from "../../../../src/vault/adapter/balancer/BalancerCompounder.sol";
import {BalancerCompounderTestConfigStorage, BalancerCompounderTestConfig} from "./BalancerCompounderTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../abstract/AbstractAdapterTest.sol";

contract BalancerCompounderTest is AbstractAdapterTest {
    using Math for uint256;

    address lpToken;
    address registry = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b; // Minter
    IGauge gauge;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new BalancerCompounderTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _gauge, ) = abi.decode(testConfig, (address, address));

        gauge = IGauge(_gauge);
        lpToken = gauge.lp_token();

        setUpBaseTest(
            IERC20(lpToken),
            address(new BalancerCompounder()),
            registry,
            10,
            "Balancer",
            false
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        _mintAsset(defaultAmount, bob);

        vm.startPrank(bob);
        asset.approve(address(adapter), defaultAmount);
        adapter.deposit(defaultAmount, bob);
        vm.stopPrank();

        assertEq(
            adapter.totalAssets(),
            adapter.convertToAssets(adapter.totalSupply()),
            string.concat("totalSupply converted != totalAssets", baseTestId)
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft BalancerCompounder ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-bc-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(gauge)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    BatchSwapStep[] swaps;
    IAsset[] assets;
    int256[] limits;
    uint256 minTradeAmount;
    address[] underlyings;

    function test__harvest() public override {
        // add BAL swap
        swaps.push(
            BatchSwapStep(
                0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
                0,
                1,
                0,
                ""
            )
        ); // trade BAL for WETH
        assets.push(IAsset(0xba100000625a3754423978a60c9317c58a424e3D)); // BAL
        assets.push(IAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)); // WETH
        limits.push(type(int256).max); // BAL limit
        limits.push(-1); // WETH limit

        // set minTradeAmounts
        minTradeAmount = 10e18;

        // set underlyings
        underlyings.push(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
        underlyings.push(0xE7e2c68d3b13d905BBb636709cF4DfD21076b9D2); // LP-Token
        underlyings.push(0xf951E335afb289353dc249e82926178EaC7DEd78); // swETH

        BalancerCompounder(address(adapter)).setHarvestValues(
            HarvestValue(
                swaps,
                assets,
                limits,
                minTradeAmount,
                0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                underlyings,
                0,
                2,
                0xe7e2c68d3b13d905bbb636709cf4dfd21076b9d20000000000000000000005ca
            )
        );

        _mintAssetAndApproveForAdapter(100e18, bob);

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 100000_000);
        vm.warp(block.timestamp + 1500000_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    // function test__harvest_no_rewards() public {
    //     // add BAL swap
    //     swaps.push(
    //         BatchSwapStep(
    //             0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
    //             0,
    //             1,
    //             0,
    //             ""
    //         )
    //     ); // trade BAL for WETH
    //     assets.push(IAsset(0xba100000625a3754423978a60c9317c58a424e3D)); // BAL
    //     assets.push(IAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)); // WETH
    //     limits.push(type(int256).max); // BAL limit
    //     limits.push(-1); // WETH limit

    //     // set minTradeAmounts
    //     minTradeAmount = 0;

    //     // set underlyings
    //     underlyings.push(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH
    //     underlyings.push(0xE7e2c68d3b13d905BBb636709cF4DfD21076b9D2); // LP-Token
    //     underlyings.push(0xf951E335afb289353dc249e82926178EaC7DEd78); // swETH

    //     BalancerCompounder(address(adapter)).setHarvestValues(
    //         HarvestValue(
    //             swaps,
    //             assets,
    //             limits,
    //             minTradeAmount,
    //             0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
    //             underlyings,
    //             0,
    //             2,
    //             0xe7e2c68d3b13d905bbb636709cf4dfd21076b9d20000000000000000000005ca
    //         )
    //     );

    //     _mintAssetAndApproveForAdapter(100e18, bob);

    //     vm.prank(bob);
    //     adapter.deposit(100e18, bob);

    //     uint256 oldTa = adapter.totalAssets();

    //     adapter.harvest();

    //     assertEq(adapter.totalAssets(), oldTa);
    // }
}
