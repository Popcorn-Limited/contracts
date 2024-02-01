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

        address[] memory swapTokens = new address[](3);
        swapTokens[0] = arb;
        swapTokens[1] = _asset;
        swapTokens[2] = _lpToken;

        CurveSwap[] memory swaps = new CurveSwap[](3);

        /// @dev for some reason overwriting the swapParam would use only the latest iteration in the swaps storage. Therefore i needed to split these.
        uint256[5][5] memory swapParams1; // [i, j, swap type, pool_type, n_coins]
        uint256[5][5] memory swapParams2; // [i, j, swap type, pool_type, n_coins]
        uint256[5][5] memory swapParams3; // [i, j, swap type, pool_type, n_coins]

        address[5] memory pools;

        // arb->crvUSD->lp swap
        address[11] memory rewardRoute = [
            arb, // arb
            0x845C8bc94610807fCbaB5dd2bc7aC9DAbaFf3c55, // arb / crvUSD pool
            0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5, // crvUSD
            _lpToken,
            _asset, // @dev -- this previously also _lpToken if we can figure out the router issue
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // arb->crvUSD->lp swap params
        swapParams1[0] = [uint256(1), 0, 2, 0, 0]; // arbIndex, crvUsdIndex, exchange_underlying, irrelevant, irrelevant
        //swapParams1[1] = [uint256(0), 0, 4, 0, 2]; // crvUsdIndex, irrelevant, add_liquidity, irrelevant, 2 coins
        swapParams1[1] = [uint256(0), 1, 2, 0, 0]; // crvUsdIndex, irrelevant, exchange_underlying, irrelevant, irrelevant

        swaps[0] = CurveSwap(rewardRoute, swapParams1, pools);
        minTradeAmounts[0] = uint256(1e16);

        // asset->lp swap
        rewardRoute = [
            _asset,
            _lpToken,
            _lpToken,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // asset->lp swap params
        swapParams2[0] = [uint256(1), 0, 4, 0, 2]; // fraxIndex, irrelevant, add_liquidity, irrelevant, 2 coins

        swaps[1] = CurveSwap(rewardRoute, swapParams2, pools);

        // lp->asset swap
        rewardRoute = [
            _lpToken,
            _lpToken,
            _asset,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        // lp->asset swap params
        swapParams3[0] = [uint256(0), 1, 6, 3, 0]; // irrelevant, fraxIndex, remove_liquidity, stable, irrelevant

        swaps[2] = CurveSwap(rewardRoute, swapParams3, pools);

        CurveGaugeSingleAssetCompounder(address(adapter)).setHarvestValues(
            0xF0d4c12A5768D806021F80a262B4d39d26C58b8D, // curve router
            rewardTokens,
            minTradeAmounts,
            swapTokens,
            swaps
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

    function test__stuff() public {
        _mintAssetAndApproveForAdapter(100e18, bob);
        vm.prank(bob);
        adapter.deposit(100e18, bob);

        uint256 shares = adapter.balanceOf(bob);

        uint256 prevWithdraw = adapter.previewWithdraw(10e18);
        emit log_named_uint("shares", shares);
        emit log_named_uint("prevRedeem", adapter.previewRedeem(prevWithdraw));
        emit log_named_uint("prevWithdraw", prevWithdraw);

        uint256 lpBal = IERC20(address(gauge)).balanceOf(address(adapter));
        uint256 withdrawable = ICurveLp(lpToken).calc_withdraw_one_coin(
            lpBal,
            1
        );
        emit log_named_uint("withdrawable", withdrawable);

        vm.prank(bob);
        adapter.withdraw(10e18, bob, bob);
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

        vm.expectEmit(false, false, false, true, address(adapter));
        emit Initialized(uint8(1));
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
                "VaultCraft CurveGauge ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcCrvG-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            IERC20(lpToken).allowance(address(adapter), address(gauge)),
            type(uint256).max,
            "allowance"
        );
    }

    function test__correct_harvest_values() public {
        CurveGaugeSingleAssetCompounder strategy = CurveGaugeSingleAssetCompounder(
                address(adapter)
            );

        address[] memory _rewardTokens = strategy.rewardTokens();
        address[] memory _swapTokens = strategy.getSwapTokens();

        assertEq(_rewardTokens.length, 1);
        assertEq(_rewardTokens[0], arb);

        assertEq(_swapTokens.length, 3);
        assertEq(_swapTokens[0], arb);
        assertEq(_swapTokens[1], address(asset));
        assertEq(_swapTokens[2], lpToken);

        address[11] memory _route = strategy.getRoute(address(asset));
        assertEq(_route[0], address(asset));
        assertEq(_route[1], address(lpToken));
        assertEq(_route[2], address(lpToken));
        assertEq(_route[3], address(0));

        _route = strategy.getRoute(address(lpToken));
        assertEq(_route[0], address(lpToken));
        assertEq(_route[1], address(lpToken));
        assertEq(_route[2], address(asset));
        assertEq(_route[3], address(0));

        _route = strategy.getRoute(address(arb));
        assertEq(_route[0], address(arb));
        assertEq(
            _route[1],
            address(0x845C8bc94610807fCbaB5dd2bc7aC9DAbaFf3c55)
        );
        assertEq(
            _route[2],
            address(0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5)
        );
        assertEq(_route[3], address(lpToken));
        assertEq(_route[4], address(lpToken));
        assertEq(_route[5], address(0));

        uint256[5][5] memory _swapParams = strategy.getSwapParams(
            address(asset)
        );
        assertEq(_swapParams[0][0], 1);
        assertEq(_swapParams[0][1], 1);
        assertEq(_swapParams[0][2], 1);
        assertEq(_swapParams[0][3], 1);
        assertEq(_swapParams[0][4], 1);

        _swapParams = strategy.getSwapParams(address(lpToken));
        assertEq(_swapParams[0][0], 2);
        assertEq(_swapParams[0][1], 2);
        assertEq(_swapParams[0][2], 2);
        assertEq(_swapParams[0][3], 2);
        assertEq(_swapParams[0][4], 2);

        _swapParams = strategy.getSwapParams(address(arb));
        assertEq(_swapParams[0][0], 2);
        assertEq(_swapParams[0][1], 2);
        assertEq(_swapParams[0][2], 2);
        assertEq(_swapParams[0][3], 2);
        assertEq(_swapParams[0][4], 2);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForAdapter(10000e18, bob);

        vm.prank(bob);
        adapter.deposit(10000e18, bob);

        uint256 oldTa = adapter.totalAssets();

        //vm.roll(block.number + 1000);
        vm.rollFork(forkId, 176245622);

        // emit log_named_uint(
        //     "claimable",
        //     IGauge(gauge).claimable_rewards(address(adapter), arb)
        // );

        adapter.harvest();

        // emit log_named_uint("adapter.totalAssets()", adapter.totalAssets());
        // emit log_named_uint("oldTa", oldTa);

        // assertGt(adapter.totalAssets(), oldTa);
    }

    function test__harvest_no_rewards() public {
        _mintAssetAndApproveForAdapter(100e18, bob);

        vm.prank(bob);
        adapter.deposit(100e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 150);

        emit log_named_uint(
            "claimable",
            IGauge(gauge).claimable_rewards(address(adapter), arb)
        );

        adapter.harvest();

        assertEq(adapter.totalAssets(), oldTa);
    }
}
