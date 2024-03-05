// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {AuraCompounder, SafeERC20, IERC20, IERC20Metadata, Math, IAuraBooster, IAuraRewards, IAuraStaking, IStrategy, IAdapter, IWithRewards, IAsset, BatchSwapStep} from "../../../../src/vault/adapter/aura/AuraCompounderVEC.sol";
import {AuraCompounderTestConfigStorage, AuraCompounderTestConfig} from "./AuraCompounderTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage} from "../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../utils/mocks/MockStrategyClaimer.sol";

contract AuraCompounderTest is AbstractAdapterTest {
    using Math for uint256;

    IAuraBooster public auraBooster =
        IAuraBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);
    IAuraRewards public auraRewards;
    IAuraStaking public auraStaking;

    address public auraLpToken;
    uint256 public pid;

    BatchSwapStep[][] swaps;
    IAsset[][] assets;
    int256[][] limits;
    uint256[] minTradeAmounts;
    address[] underlyings;

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new AuraCompounderTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (
            uint256 _pid,,,
        ) = abi.decode(testConfig, (uint256, address, bytes32, address[]));

        pid = _pid;

        auraStaking = IAuraStaking(auraBooster.stakerRewards());

        (
            address balancerLpToken,
            address _auraLpToken,
            address _auraGauge,
            address _auraRewards,
            ,

        ) = auraBooster.poolInfo(pid);

        auraRewards = IAuraRewards(_auraRewards);
        auraLpToken = _auraLpToken;

        setUpBaseTest(
            IERC20(balancerLpToken),
            address(new AuraCompounder()),
            address(auraBooster),
            10,
            "Aura",
            false
        );

        vm.label(address(auraBooster), "auraBooster");
        vm.label(address(auraRewards), "auraRewards");
        vm.label(address(auraStaking), "auraStaking");
        vm.label(address(auraLpToken), "auraLpToken");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        // add BAL swap
        swaps.push();
        swaps[0].push(
           // trade BAL for WETH 
           BatchSwapStep(
                0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014,
                0,
                1,
                0,
                ""
            )
        );
        assets.push([IAsset(0xba100000625a3754423978a60c9317c58a424e3D), IAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)]); // BAL
        limits.push([type(int).max, type(int).max]);

        // add AURA swap
        swaps.push();
        swaps[1].push(
            // trade AURA for WETH
            BatchSwapStep(
                0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274,
                0,
                1,
                0,
                ""
            )
        ); 
        assets.push([IAsset(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF), IAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)]); // AURA
        limits.push([type(int).max, type(int).max]);

        // set minTradeAmounts
        minTradeAmounts.push(0);
        minTradeAmounts.push(0);

        AuraCompounder(address(adapter)).setHarvestValues(
            swaps,
            assets,
            limits,
            minTradeAmounts,
            IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            2,
            1,
            2
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
                "VaultCraft Aura ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcAu-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(auraBooster)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForAdapter(10000e18, bob);

        vm.prank(bob);
        adapter.deposit(10000e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__harvest_no_rewards() public {
        _mintAssetAndApproveForAdapter(100e18, bob);

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        adapter.harvest();

        assertEq(adapter.totalAssets(), oldTa);
    }

    function test__recover() public {
        _mintAssetAndApproveForAdapter(10000e18, bob);

        vm.prank(bob);
        adapter.deposit(10000e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 100);
        vm.warp(block.timestamp + 1500);

        AuraCompounder(address(adapter)).claim();

        emit log_uint(IERC20(0xba100000625a3754423978a60c9317c58a424e3D).balanceOf(address(adapter)));
        emit log_uint(IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF).balanceOf(address(adapter)));
        emit log_uint(IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2).balanceOf(address(adapter)));
        emit log_uint(IERC20(0x1BB9b64927e0C5e207C9DB4093b3738Eef5D8447).balanceOf(address(adapter)));

        AuraCompounder(address(adapter)).recoverToken(0x1BB9b64927e0C5e207C9DB4093b3738Eef5D8447,address(this));

        assertGt(IERC20(0x1BB9b64927e0C5e207C9DB4093b3738Eef5D8447).balanceOf(address(this)), 0);
    }
}
