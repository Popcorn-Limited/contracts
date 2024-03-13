// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {CurveGaugeSingleAssetCompounder, SafeERC20, IERC20, IERC20Metadata, Math, CurveSwap, ICurveLp, IGauge} from "../../../../../../src/vault/adapter/curve/gauge/other/CurveGaugeSingleAssetCompounder.sol";
import {CurveGaugeSingleAssetCompounderTestConfigStorage, CurveGaugeSingleAssetCompounderTestConfig} from "./CurveGaugeSingleAssetCompounderTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../../abstract/AbstractAdapterTest.sol";
import {MockStrategyClaimer} from "../../../../../utils/mocks/MockStrategyClaimer.sol";

contract CurveGaugeSingleAssetCompounderTest is AbstractAdapterTest {
    using Math for uint256;

    address gauge;
    address lpToken;
    address arb = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    uint256 forkId;

    uint256 constant DISCOUNT_BPS = 50;

    function setUp() public {
        forkId = vm.createSelectFork(vm.rpcUrl("arbitrum"), 176205000);
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new CurveGaugeSingleAssetCompounderTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (
            address _asset,
            address _lpToken,
            address _gauge,
            int128 _indexIn
        ) = abi.decode(
                testConfigStorage.getTestConfig(0),
                (address, address, address, int128)
            );

        gauge = _gauge;
        lpToken = _lpToken;

        setUpBaseTest(
            IERC20(_asset),
            address(new CurveGaugeSingleAssetCompounder()),
            address(0),
            10,
            "Curve",
            false
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_lpToken, _gauge, _indexIn)
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = arb;
        uint256[] memory minTradeAmounts = new uint256[](1);
        minTradeAmounts[0] = 0;

        CurveSwap[] memory swaps = new CurveSwap[](3);
        uint256[5][5] memory swapParams; // [i, j, swap type, pool_type, n_coins]
        address[5] memory pools;

        // arb->crvUSD->lp swap
        address[11] memory rewardRoute = [
            arb, // arb
            0x845C8bc94610807fCbaB5dd2bc7aC9DAbaFf3c55, // arb / crvUSD pool
            0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5, // crvUSD
            _lpToken,
            _asset,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // arb->crvUSD->lp swap params
        swapParams[0] = [uint256(1), 0, 2, 0, 0]; // arbIndex, crvUsdIndex, exchange_underlying, irrelevant, irrelevant
        swapParams[1] = [uint256(0), 1, 1, 1, 0]; // crvUsdIndex, irrelevant, exchange, stable, irrelevant

        swaps[0] = CurveSwap(rewardRoute, swapParams, pools);
        minTradeAmounts[0] = uint256(1e16);

        CurveGaugeSingleAssetCompounder(address(adapter)).setHarvestValues(
            0xF0d4c12A5768D806021F80a262B4d39d26C58b8D, // curve router
            rewardTokens,
            minTradeAmounts,
            swaps,
            uint256(50)
        );

        vm.label(address(arb), "arb");
        vm.label(address(lpToken), "lpToken");
        vm.label(address(gauge), "gauge");
        vm.label(address(asset), "asset");
        vm.label(address(adapter), "adapter");
        vm.label(address(this), "test");

        maxAssets = 100_000 * 1e18;
        maxShares = 100 * 1e27;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(asset),
            address(gauge),
            asset.balanceOf(address(gauge)) + amount
        );
    }

    // Verify that totalAssets returns the expected amount
    function verify_totalAssets() public override {
        // Make sure totalAssets isnt 0
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

    function test__initialization() public override {
        createAdapter();
        uint256 callTime = block.timestamp;

        (
            address _asset,
            address _lpToken,
            address _gauge,
            int128 _indexIn
        ) = abi.decode(
                testConfigStorage.getTestConfig(0),
                (address, address, address, int128)
            );

        adapter.initialize(
            abi.encode(_asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_lpToken, _gauge, _indexIn)
        );

        assertEq(adapter.owner(), address(this), "owner");
        assertEq(adapter.strategy(), address(0), "strategy");
        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
        assertEq(adapter.strategyConfig(), "", "strategyConfig");
        assertEq(
            IERC20Metadata(address(adapter)).decimals(),
            IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
            "decimals"
        );

        verify_adapterInit();
    }

    function verify_adapterInit() public override {
        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft CurveGaugeSingleAssetCompounder ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-sccrv-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            IERC20(lpToken).allowance(address(adapter), address(gauge)),
            type(uint256).max,
            "allowance"
        );
        assertEq(
            IERC20(asset).allowance(address(adapter), address(lpToken)),
            type(uint256).max,
            "allowance"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSING
    //////////////////////////////////////////////////////////////*/

    function test__unpause() public override {
        uint defaultAmount = 1e18;
        uint _delta_ = 1e16;
        _mintAssetAndApproveForAdapter(defaultAmount * 3, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();
        uint256 oldIouBalance = iouBalance();

        adapter.pause();
        adapter.unpause();

        // We simply deposit back into the external protocol
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            52510 * 1e18,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            0,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), oldIouBalance, _delta_, "iou balance");

        // Deposit and mint dont revert
        vm.startPrank(bob);
        adapter.deposit(defaultAmount, bob);
        adapter.mint(defaultAmount, bob);
    }

    function test__pause() public override {
        uint _delta_ = 1e16;
        uint defaultAmount = 1e18;
        _mintAssetAndApproveForAdapter(defaultAmount, bob);

        vm.prank(bob);
        adapter.deposit(defaultAmount, bob);

        uint256 oldTotalAssets = adapter.totalAssets();
        uint256 oldTotalSupply = adapter.totalSupply();

        adapter.pause();

        // We simply withdraw into the adapter
        // TotalSupply and Assets dont change
        assertApproxEqAbs(
            oldTotalAssets,
            adapter.totalAssets(),
            _delta_,
            "totalAssets"
        );
        assertApproxEqAbs(
            oldTotalSupply,
            adapter.totalSupply(),
            _delta_,
            "totalSupply"
        );
        assertApproxEqAbs(
            asset.balanceOf(address(adapter)),
            oldTotalAssets,
            _delta_,
            "asset balance"
        );
        assertApproxEqAbs(iouBalance(), 0, _delta_, "iou balance");

        vm.startPrank(bob);
        // Deposit and mint are paused (maxDeposit/maxMint are set to 0 on pause)
        vm.expectRevert();
        adapter.deposit(defaultAmount, bob);

        vm.expectRevert();
        adapter.mint(defaultAmount, bob);

        // Withdraw and Redeem dont revert
        adapter.withdraw(defaultAmount / 10, bob, bob);
        adapter.redeem(defaultAmount / 10, bob, bob);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForAdapter(1000e18, bob);

        vm.prank(bob);
        adapter.deposit(1000e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.warp(block.timestamp + 150_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    function test__harvest_no_rewards() public {
        _mintAssetAndApproveForAdapter(100e18, bob);

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.warp(block.timestamp + 150);

        adapter.harvest();

        assertEq(adapter.totalAssets(), oldTa);
    }
}
