// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {CurveGaugeCompounder, SafeERC20, IERC20, IERC20Metadata, Math, CurveSwap, ICurveLp, IGauge} from "../../../../../../src/vault/adapter/curve/gauge/mainnet/CurveGaugeCompounder.sol";
import {CurveGaugeCompounderTestConfigStorage, CurveGaugeCompounderTestConfig} from "./CurveGaugeCompounderTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../../../abstract/AbstractAdapterTest.sol";

contract CurveGaugeCompounderTest is AbstractAdapterTest {
    using Math for uint256;

    address gauge;
    uint256 forkId;
    address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address depositAsset;

    function setUp() public {
        forkId = vm.createSelectFork(vm.rpcUrl("mainnet"), 19138838);
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new CurveGaugeCompounderTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, address _gauge, address _pool) = abi.decode(
            testConfigStorage.getTestConfig(0),
            (address, address, address)
        );

        gauge = _gauge;

        setUpBaseTest(
            IERC20(_asset),
            address(new CurveGaugeCompounder()),
            address(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0),
            10,
            "Curve",
            false
        );

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_gauge, _pool)
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = crv;
        uint256[] memory minTradeAmounts = new uint256[](1);
        minTradeAmounts[0] = uint256(1e16);

        CurveSwap[] memory swaps = new CurveSwap[](1);
        uint256[5][5] memory swapParams; // [i, j, swap type, pool_type, n_coins]
        address[5] memory pools;

        int128 indexIn = int128(1); // WETH index

        // crv->weth->weETH swap
        address[11] memory rewardRoute = [
            crv, // crv
            0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14, // triCRV pool
            0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E, // crvUSD
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // crv->crvUSD swap params
        swapParams[0] = [uint256(2), 0, 1, 0, 0]; // crvIndex, wethIndex, exchange, irrelevant, irrelevant

        swaps[0] = CurveSwap(rewardRoute, swapParams, pools);

        CurveGaugeCompounder(address(adapter)).setHarvestValues(
            0xF0d4c12A5768D806021F80a262B4d39d26C58b8D, // curve router
            rewardTokens,
            minTradeAmounts,
            swaps,
            indexIn
        );

        depositAsset = ICurveLp(address(asset)).coins(
            uint256(uint128(indexIn))
        );

        vm.label(address(crv), "crv");
        vm.label(address(gauge), "gauge");
        vm.label(address(depositAsset), "depositAsset");
        vm.label(address(asset), "asset");
        vm.label(address(adapter), "adapter");
        vm.label(address(this), "test");

        maxAssets = 100_000 * 1e18;
        maxShares = 100 * 1e18;
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

        (address _asset, address _gauge, address _pool) = abi.decode(
            testConfigStorage.getTestConfig(0),
            (address, address, address)
        );

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
        adapter.initialize(
            abi.encode(_asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            abi.encode(_gauge, _pool)
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
                "VaultCraft CurveGaugeCompounder ",
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
            IERC20(asset).allowance(address(adapter), address(gauge)),
            type(uint256).max,
            "allowance gauge"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                PAUSING
    //////////////////////////////////////////////////////////////*/

    function test__unpause() public override {
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

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForAdapter(100e18, bob);

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 100000);
        vm.warp(block.timestamp + 1500_000);

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
}
