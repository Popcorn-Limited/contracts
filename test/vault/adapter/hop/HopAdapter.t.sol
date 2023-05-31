// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {HopAdapter, SafeERC20, IERC20, IERC20Metadata, Math, ILiquidityPool, IStakingRewards} from "../../../../src/vault/adapter/hop/HopAdapter.sol";
import {HopTestConfigStorage, HopTestConfig} from "./HopTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract HopAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    // Note: using the hop liquidity pool contract
    // https://optimistic.etherscan.io/address/0xaa30d6bba6285d0585722e2440ff89e23ef68864#writeContract
    ILiquidityPool public liquidityPool =
        ILiquidityPool(0xaa30D6bba6285d0585722e2440Ff89E23EF68864);
    //IStakingRewards public stakingRewards = IStakingRewards(0xfD49C7EE330fE060ca66feE33d49206eB96F146D);
    IStakingRewards public stakingRewards =
        IStakingRewards(0xf587B9309c603feEdf0445aF4D3B21300989e93a);
    address public LPToken;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new HopTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _liquidityPool, address _stakingRewards) = abi.decode(
            testConfig,
            (address, address)
        );
        liquidityPool = ILiquidityPool(_liquidityPool);

        stakingRewards = IStakingRewards(_stakingRewards);
        address asset = liquidityPool.getToken(0);

        ILiquidityPool.Swap memory swapStorage = liquidityPool.swapStorage();

        LPToken = swapStorage.lpToken;

        setUpBaseTest(
            IERC20(asset),
            address(new HopAdapter()),
            address(liquidityPool),
            10,
            "Hop",
            true
        );

        vm.label(address(liquidityPool), "hopLiquidityPool");
        vm.label(address(stakingRewards), "hopStakingRewards");
        vm.label(address(LPToken), "hopLPToken");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

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
        deal(address(asset), bob, defaultAmount);
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
                "VaultCraft Hop ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcHop-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(liquidityPool)),
            type(uint256).max,
            "allowance"
        );
    }
}
