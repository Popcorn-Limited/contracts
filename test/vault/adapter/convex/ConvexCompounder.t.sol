// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {ConvexCompounder, SafeERC20, IERC20, CurveSwap, ICurveLp, IERC20Metadata, Math, IConvexBooster, IConvexRewards, IWithRewards, IStrategy} from "../../../../src/vault/adapter/convex/ConvexCompounder.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "./ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract ConvexCompounderTest is AbstractAdapterTest {
    using Math for uint256;

    IConvexBooster convexBooster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    IConvexRewards convexRewards;
    ConvexCompounder adapterContract;

    uint256 pid;
    address depositAsset;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        testConfigStorage = ITestConfigStorage(
            address(new ConvexTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        uint256 _pid = abi.decode(testConfig, (uint256));
        pid = _pid;

        (address _asset, , , address _convexRewards, , ) = convexBooster
            .poolInfo(pid);
        convexRewards = IConvexRewards(_convexRewards);

        address impl = address(new ConvexCompounder());

        setUpBaseTest(
            IERC20(_asset),
            impl,
            address(convexBooster),
            10,
            "Convex",
            false
        );

        adapterContract = ConvexCompounder(address(adapter));

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );

        _setHarvestValues();

        vm.label(address(crv), "crv");
        vm.label(address(cvx), "cvx");
        vm.label(address(convexBooster), "convexBooster");
        vm.label(address(convexRewards), "convexRewards");
        vm.label(address(depositAsset), "depositAsset");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");
    }

    function _setHarvestValues() internal {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = crv;
        // rewardTokens[0] = cvx;

        uint256[] memory minTradeAmounts = new uint256[](1);
        //minTradeAmounts[0] = uint256(1e16);
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
        swapParams[0] = [uint256(2), 0, 2, 0, 0]; // crvIndex, crvUSDIndex, exchange_underlying, irrelevant, irrelevant

        swaps[0] = CurveSwap(rewardRoute, swapParams, pools);

        // crv->weth->weETH swap
        // address[11] memory rewardRoute = [
        //     cvx, // crv
        //     0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, // triCRV pool
        //     0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, // weth
        //     0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14,
        //     0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E,
        //     address(0),
        //     address(0),
        //     address(0),
        //     address(0),
        //     address(0),
        //     address(0)
        // ];
        // // crv->crvUSD swap params
        // swapParams[0] = [uint256(1), 0, 1, 2, 2]; // crvIndex, wethIndex, exchange, irrelevant, irrelevant
        // swapParams[1] = [uint256(1), 0, 1, 3, 3]; // crvIndex, wethIndex, exchange, irrelevant, irrelevant

        // //pools[0] = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;

        // swaps[0] = CurveSwap(rewardRoute, swapParams, pools);

        ConvexCompounder(address(adapter)).setHarvestValues(
            0xF0d4c12A5768D806021F80a262B4d39d26C58b8D, // curve router
            rewardTokens,
            minTradeAmounts,
            swaps,
            indexIn
        );

        depositAsset = ICurveLp(address(asset)).coins(
            uint256(uint128(indexIn))
        );
    }

    /*//////////////////////////////////////////////////////////////
                          GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

    // OPTIONAL
    function test__rewardsTokens() public override {
        address[] memory rewardTokens = IWithRewards(address(adapter))
            .rewardTokens();
        assertEq(rewardTokens[0], crv, "CRV");
        assertEq(rewardTokens[1], cvx, "CVX");
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
        _setHarvestValues();

        assertEq(adapter.asset(), address(asset), "asset");
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Convex ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vcCvx-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(convexBooster)),
            type(uint256).max,
            "allowance"
        );

        address[11] memory route = ConvexCompounder(address(adapter)).getRoute(
            address(crv)
        );
        emit log_address(route[0]);
        emit log_address(route[1]);
        emit log_address(route[2]);
        emit log_address(route[3]);
        emit log_address(route[4]);

        emit log_string("------");

        route = ConvexCompounder(address(adapter)).getRoute(address(cvx));
        emit log_address(route[0]);
        emit log_address(route[1]);
        emit log_address(route[2]);
        emit log_address(route[3]);
        emit log_address(route[4]);

        uint256[5] memory swapParams = ConvexCompounder(address(adapter))
            .getSwapParams(address(crv), uint256(0));
        emit log_uint(swapParams[0]);
        emit log_uint(swapParams[1]);
        emit log_uint(swapParams[2]);
        emit log_uint(swapParams[3]);
        emit log_uint(swapParams[4]);

        emit log_string("------");

        swapParams = ConvexCompounder(address(adapter)).getSwapParams(
            address(cvx),
            uint256(0)
        );
        emit log_uint(swapParams[0]);
        emit log_uint(swapParams[1]);
        emit log_uint(swapParams[2]);
        emit log_uint(swapParams[3]);
        emit log_uint(swapParams[4]);

        swapParams = ConvexCompounder(address(adapter)).getSwapParams(
            address(cvx),
            uint256(1)
        );
        emit log_uint(swapParams[0]);
        emit log_uint(swapParams[1]);
        emit log_uint(swapParams[2]);
        emit log_uint(swapParams[3]);
        emit log_uint(swapParams[4]);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForAdapter(100000e18, bob);

        vm.prank(bob);
        adapter.deposit(100000e18, bob);

        uint256 oldTa = adapter.totalAssets();

        vm.roll(block.number + 10_000_000);
        vm.warp(block.timestamp + 150_000_000);

        adapter.harvest();

        assertGt(adapter.totalAssets(), oldTa);
    }

    // function test__harvest_no_rewards() public {
    //     _mintAssetAndApproveForAdapter(100e18, bob);

    //     vm.prank(bob);
    //     adapter.deposit(100e18, bob);

    //     uint256 oldTa = adapter.totalAssets();

    //     adapter.harvest();

    //     assertEq(adapter.totalAssets(), oldTa);
    // }
}
