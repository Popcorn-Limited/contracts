// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {ConvexCompounder as ConvexAdapter, 
SafeERC20, IERC20, CurveRoute, IERC20Metadata, Math, IConvexBooster, 
IConvexRewards, IWithRewards, IStrategy} from "../../../../src/vault/adapter/convex/ConvexCompounder.sol";
import {ConvexTestConfigStorage, ConvexTestConfig} from "./ConvexTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract ConvexAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IConvexBooster convexBooster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address stg = address(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6);
    address crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address eth = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address usdt = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    address router = address(0x99a58482BD75cbab83b27EC03CA68fF489b5788f);

    address pool = address(0x867fe27FC2462cff8890B54DfD64E6d42a9D1aC8);
    IConvexRewards convexRewards;
    ConvexAdapter adapterContract;
    
    uint256 pid;
    
    CurveRoute lpRoute;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16991525);

        testConfigStorage = ITestConfigStorage(
            address(new ConvexTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));

        _setHarvestValues();
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
    
        address impl = address(new ConvexAdapter());

        setUpBaseTest(
            IERC20(_asset),
            impl,
            address(convexBooster),
            10,
            "Convex",
            true
        );

        vm.label(address(convexBooster), "convexBooster");
        vm.label(address(convexRewards), "convexRewards");
        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapterContract = ConvexAdapter(address(adapter));

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            externalRegistry,
            testConfig
        );
    }

    function _setHarvestValues() internal {
        CurveRoute[] memory rewardRoutes = new CurveRoute[](2);
        uint256[] memory minTradeAmounts = new uint256[](2);
        uint256[] memory maxSlippages = new uint256[](3);

        uint256[3][4] memory swapParams;

        // crv swap route
        address[9] memory rewardRoute = [
            crv,
            0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, // crv / eth
            eth,
            0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2
            usdt,
            0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3crv
            usdc,
            address(0),
            address(0)
        ];
        // crv swap params 
        swapParams[0] = [uint256(1), 0, 3];
        swapParams[1] = [uint256(2), 0, 3];
        swapParams[2] = [uint256(2), 1, 1];

        rewardRoutes[0] = CurveRoute(rewardRoute, swapParams);
        minTradeAmounts[0] = uint256(1e16);
        maxSlippages[0] = uint256(1e17);

        // cvx swap route
        rewardRoute = [
            cvx,
            0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, // cvx / eth
            eth,
            0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, // tricrypto2
            usdt,
            0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, // 3crv
            usdc,
            address(0),
            address(0)
        ];

        rewardRoutes[1] = CurveRoute(rewardRoute, swapParams);
        minTradeAmounts[1] = uint256(1e16);
        maxSlippages[1] = uint256(1e17);

        rewardRoute = [
            usdc,
            0x3211C6cBeF1429da3D0d58494938299C92Ad5860, // stg / usdc
            stg,
            pool,
            address(asset),
            address(0),
            address(0),
            address(0),
            address(0)
        ];

        uint256[3][4] memory swapLPParams;

        swapLPParams[0] = [uint256(1), 0, 3];
        swapLPParams[1] = [uint256(0), 0, 7];
        lpRoute = CurveRoute({route:rewardRoute, swapParams:swapLPParams});

        adapterContract.setHarvestValues(router, usdc, minTradeAmounts, maxSlippages, lpRoute, rewardRoutes);
    }

    /*//////////////////////////////////////////////////////////////
                          GENERAL VIEWS
    //////////////////////////////////////////////////////////////*/

    // OPTIONAL
    function test__rewardsTokens() public override {
        address[] memory rewardTokens = IWithRewards(address(adapter))
            .rewardTokens();
        address CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        assertEq(rewardTokens[0], CRV, "CRV");
        assertEq(rewardTokens[1], CVX, "CVX");
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function verify_adapterInit() public override {
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
    }

    /*//////////////////////////////////////////////////////////////
                              CLAIM
    //////////////////////////////////////////////////////////////*/

    function test__harvestAndCompound() public {
        _mintAssetAndApproveForAdapter(1000e18, bob);

        vm.prank(bob);
        adapter.deposit(1000e18, bob);
        vm.warp(block.timestamp + 90 days);

        uint256 assetBalBefore = adapter.totalAssets();
        uint256 vaultSharesBefore = adapter.totalSupply();
        uint256 previewWithdrawBefore = adapter.previewRedeem(1e18);

        adapter.harvest();

        address[] memory rewardTokens = IWithRewards(address(adapter))
            .rewardTokens();
        assertEq(rewardTokens[0], 0xD533a949740bb3306d119CC777fa900bA034cd52); // CRV
        assertEq(rewardTokens[1], 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B); // CVX

        // assert underlying asset increased
        assertGt(adapter.totalAssets(), assetBalBefore);
        // assert total supply has not changed 
        assertEq(adapter.totalSupply(), vaultSharesBefore);
        // assert rate increased
        assertGt(adapter.previewRedeem(1e18), previewWithdrawBefore);

        // assert vault doesn't hold any reward token - ie swapped whole balance claimed
        assertEq(IERC20(rewardTokens[0]).balanceOf(address(adapter)), 0);
        assertEq(IERC20(rewardTokens[1]).balanceOf(address(adapter)), 0);
    }
}
