// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {PendleWstETHAdapter, BalancerRewardTokenData, IPendleRouter, IPendleMarket, IPendleSYToken, Math, IERC20, IERC20Metadata} from "../../../../src/vault/adapter/pendle/PendleWstETHAdapter.sol";
import {PendleTestConfigStorage, PendleTestConfig} from "./PendleTestConfigStorage.sol";
import {AbstractAdapterTest, ITestConfigStorage, IAdapter} from "../abstract/AbstractAdapterTest.sol";

contract wstETHPendleAdapterTest is AbstractAdapterTest {
    using Math for uint256;

    IPendleRouter pendleRouter = IPendleRouter(0x00000000005BBB0EF59571E58418F9a4357b68A0);
    
    IPendleSYToken synToken;
    address pendleMarket;
    address syToken = address(0xcbC72d92b2dc8187414F6734718563898740C0BC);
    address yieldToken = address(0xA53ad7E3A87546CCa450992d54d517c3C939c2BF);
    address principalToken = address(0xcf44E8402a99Db82d2AccCC4d9354657Be2121Db);
    address pendleToken = address(0x808507121B80c02388fAd14726482e061B8da827);
    address WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address wstETH = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    PendleWstETHAdapter adapterContract;

    uint256 slippage;
    uint32 twapDuration; 

    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);

        testConfigStorage = ITestConfigStorage(
            address(new PendleTestConfigStorage())
        );

        _setUpTest(testConfigStorage.getTestConfig(0));
    }

    function overrideSetup(bytes memory testConfig) public override {
        _setUpTest(testConfig);
    }

    function _setUpTest(bytes memory testConfig) internal {
        (address _asset, address _market, uint256 _slippage, uint32 _twapDuration) = abi.decode(
            testConfig,
            (address, address, uint256, uint32)
        );

        pendleMarket = _market;
        slippage = _slippage;
        twapDuration = _twapDuration;

        (address _synToken, ,) = IPendleMarket(pendleMarket).readTokens();
        synToken = IPendleSYToken(_synToken);

        setUpBaseTest(
            IERC20(_asset),
            address(new PendleWstETHAdapter()),
            address(pendleRouter),
            10,
            "Pendle ",
            false
        );

        vm.label(address(asset), "asset");
        vm.label(address(this), "test");

        adapter.initialize(
            abi.encode(asset, address(this), address(0), 0, sigs, ""),
            externalRegistry,
            abi.encode(pendleMarket, slippage, twapDuration)
        );

        adapterContract = PendleWstETHAdapter(payable(address(adapter)));

        defaultAmount = 10 ** IERC20Metadata(address(asset)).decimals();
        minFuzz = defaultAmount * 10_000;
        raise = defaultAmount * 100_000_000;
        maxAssets = defaultAmount * 1_000_000;
        maxShares = maxAssets / 2;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function iouBalance() public view override returns (uint256) {
        return IERC20(pendleMarket).balanceOf(address(adapter));
    }

    function increasePricePerShare(uint256 amount) public override {
        deal(
            address(pendleMarket),
            address(adapter),
            amount
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            address(pendleRouter),
            abi.encode(pendleMarket, slippage, twapDuration)
        );

        assertEq(adapter.owner(), address(this), "owner");
        assertEq(adapter.strategy(), address(strategy), "strategy");
        assertEq(adapter.harvestCooldown(), 0, "harvestCooldown");
        assertEq(adapter.strategyConfig(), "", "strategyConfig");
        assertEq(
            IERC20Metadata(address(adapter)).decimals(),
            IERC20Metadata(address(asset)).decimals() + adapter.decimalOffset(),
            "decimals"
        );

        verify_adapterInit();
    }

    function test_depositWithdraw() public {
        assertEq(IERC20(pendleMarket).balanceOf(address(adapter)), 0);
        
        uint256 amount = 1 ether;
        deal(adapter.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(adapter.asset()).approve(address(adapter), type(uint256).max);
        adapter.deposit(amount, bob);

        assertGt(IERC20(pendleMarket).balanceOf(address(adapter)), 0);
        uint256 totAssets = adapter.totalAssets();

        adapter.redeem(IERC20(address(adapter)).balanceOf(address(bob)), bob, bob);
        vm.stopPrank();

        assertEq(IERC20(pendleMarket).balanceOf(address(adapter)), 0);
        assertEq(IERC20(adapter.asset()).balanceOf(bob), totAssets);
    }

    function test__harvest() public override {
        adapter.toggleAutoHarvest();

        uint256 amount = 1 ether;
        deal(adapter.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(adapter.asset()).approve(address(adapter), type(uint256).max);
        adapter.deposit(amount, bob);
        vm.stopPrank();

        uint256 totAssetsBefore = adapter.totalAssets();

        // only pendle reward
        BalancerRewardTokenData[] memory rewData = new BalancerRewardTokenData[](1);
        
        bytes32[] memory pools = new bytes32[](2);
        pools[0] = hex"fd1cf6fd41f229ca86ada0584c63c49c3d66bbc9000200000000000000000438"; // pendle/weth
        pools[1] = hex"93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2"; // weth/wstETH

        rewData[0].poolIds = pools;
        rewData[0].minTradeAmount = 0;

        rewData[0].pathAddresses = new address[](3);
        rewData[0].pathAddresses[0] = pendleToken;
        rewData[0].pathAddresses[1] = WETH;
        rewData[0].pathAddresses[2] = wstETH;

        // set harvest data
        adapterContract.setHarvestData(rewData);

        vm.roll(block.number + 1_000_000);
        vm.warp(block.timestamp + 15_000_000);

        adapter.harvest();

        // total assets have increased
        assertGt(adapter.totalAssets(), totAssetsBefore);
    }

    function verify_adapterInit() public override {
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat(
                "VaultCraft Pendle ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            asset.allowance(address(adapter), address(pendleRouter)),
            type(uint256).max,
            "allowance"
        );

        // Revert if asset is not compatible with pendle market
        address invalidAsset = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        createAdapter();
        vm.expectRevert();
        adapter.initialize(
            abi.encode(invalidAsset, address(this), strategy, 0, sigs, ""),
            address(pendleRouter),
            abi.encode(pendleMarket)
        );

        assertGt(adapterContract.lastRate(), 0);
    }
}
