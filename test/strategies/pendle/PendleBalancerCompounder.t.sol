// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {PendleBalancerCompounder} from "../../../src/strategies/pendle/PendleBalancerCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";

contract PendleBalancerCompounderTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IPendleRouter pendleRouter = IPendleRouter(0x888888888889758F76e7103c6CbF23ABbF58F946);
    address balancerRouter = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IPendleSYToken synToken;
    address pendleMarket;
    address pendleToken = address(0x808507121B80c02388fAd14726482e061B8da827);
    address WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address pendleRouterStatic;

    PendleAdapterBalancerHarvest adapterContract;

    uint256 swapDelay;

    function setUp() public {
        _setUpBaseTest(1, "./test/strategies/pendle/PendleBalancerCompounderTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        address minter = json_.readAddress(string.concat(".configs[", index_, "].specific.init.minter"));

        address gauge = json_.readAddress(string.concat(".configs[", index_, "].specific.init.gauge"));

        // Deploy Strategy
        BalancerCompounder strategy = new BalancerCompounder();

        strategy.initialize(testConfig_.asset, address(this), true, abi.encode(minter, gauge));

        // Set Harvest values
        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function _setHarvestValues(string memory json_, string memory index_, address strategy) internal {
        // Read harvest values
        address balancerVault_ =
            json_.readAddress(string.concat(".configs[", index_, "].specific.harvest.balancerVault"));

        HarvestValues memory harvestValues_ = abi.decode(
            json_.parseRaw(string.concat(".configs[", index_, "].specific.harvest.harvestValues")), (HarvestValues)
        );

        TradePath[] memory tradePaths_ = _getTradePaths(json_, index_);

        // Set harvest values
        PendleBalancerCompounder(strategy).setHarvestValues(balancerVault_, tradePaths_);
    }

    function _getTradePaths(string memory json_, string memory index_) internal pure returns (TradePath[] memory) {
        uint256 swapLen = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.tradePaths.length"));

        TradePath[] memory tradePaths_ = new TradePath[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory assetAddresses = json_.readAddressArray(
                string.concat(".configs[", index_, "].specific.harvest.tradePaths.structs[", vm.toString(i), "].assets")
            );
            IAsset[] memory assets = new IAsset[](assetAddresses.length);
            for (uint256 n; n < assetAddresses.length; n++) {
                assets[n] = IAsset(assetAddresses[n]);
            }

            int256[] memory limits = json_.readIntArray(
                string.concat(".configs[", index_, "].specific.harvest.tradePaths.structs[", vm.toString(i), "].limits")
            );

            BatchSwapStep[] memory swapSteps = abi.decode(
                json_.parseRaw(
                    string.concat(
                        ".configs[", index_, "].specific.harvest.tradePaths.structs[", vm.toString(i), "].swaps"
                    )
                ),
                (BatchSwapStep[])
            );

            tradePaths_[i] = TradePath({assets: assets, limits: limits, swaps: abi.encode(swapSteps)});
        }

        return tradePaths_;
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function iouBalance() public view override returns (uint256) {
        return IERC20(pendleMarket).balanceOf(address(adapter));
    }

    function increasePricePerShare(uint256 amount) public override {
        deal(address(asset), address(pendleMarket), IERC20(address(asset)).balanceOf(address(pendleMarket)) + amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        createAdapter();

        adapter.initialize(
            abi.encode(asset, address(this), strategy, 0, sigs, ""),
            address(pendleRouter),
            abi.encode(pendleMarket, pendleRouterStatic, swapDelay)
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

    // override tests that uses multiple configurations
    // as this adapter only wants wstETH
    function test__deposit(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(0));
            uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

            _mintAssetAndApproveForAdapter(amount, bob);

            prop_deposit(bob, bob, amount, testId);

            increasePricePerShare(raise);

            _mintAssetAndApproveForAdapter(amount, bob);
            prop_deposit(bob, alice, amount, testId);
        }
    }

    function test__mint(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(0));
            uint256 amount = bound(uint256(fuzzAmount), minShares, maxShares);

            _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);

            prop_mint(bob, bob, amount, testId);

            increasePricePerShare(raise);

            _mintAssetAndApproveForAdapter(adapter.previewMint(amount), bob);

            prop_mint(bob, alice, amount, testId);
        }
    }

    function test__redeem(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(0));
            uint256 amount = bound(uint256(fuzzAmount), minShares, maxShares);

            uint256 reqAssets = adapter.previewMint(amount);
            _mintAssetAndApproveForAdapter(reqAssets, bob);

            vm.prank(bob);
            adapter.deposit(reqAssets, bob);
            prop_redeem(bob, bob, adapter.maxRedeem(bob), testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);
            prop_redeem(alice, bob, adapter.maxRedeem(bob), testId);
        }
    }

    function test__withdraw(uint8 fuzzAmount) public override {
        uint8 len = uint8(testConfigStorage.getTestConfigLength());
        for (uint8 i; i < len; i++) {
            if (i > 0) overrideSetup(testConfigStorage.getTestConfig(0));
            uint256 amount = bound(uint256(fuzzAmount), minFuzz, maxAssets);

            uint256 reqAssets = adapter.previewMint(adapter.previewWithdraw(amount));
            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            prop_withdraw(bob, bob, adapter.maxWithdraw(bob), testId);

            _mintAssetAndApproveForAdapter(reqAssets, bob);
            vm.prank(bob);
            adapter.deposit(reqAssets, bob);

            increasePricePerShare(raise);

            vm.prank(bob);
            adapter.approve(alice, type(uint256).max);

            prop_withdraw(alice, bob, adapter.maxWithdraw(bob), testId);
        }
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
        rewData[0].pathAddresses[2] = adapter.asset();

        // set harvest data
        adapterContract.setHarvestData(balancerRouter, rewData);

        vm.roll(block.number + 1_000_000);
        vm.warp(block.timestamp + 15_000_000);

        uint256 totAssetsBefore = adapter.totalAssets();

        adapter.harvest();

        // total assets have increased
        assertGt(adapter.totalAssets(), totAssetsBefore);
    }

    function verify_adapterInit() public override {
        assertEq(
            IERC20Metadata(address(adapter)).name(),
            string.concat("VaultCraft Pendle ", IERC20Metadata(address(asset)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(adapter)).symbol(),
            string.concat("vc-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(asset.allowance(address(adapter), address(pendleRouter)), type(uint256).max, "allowance");
    }

    function testFail_invalidToken() public {
        // Revert if asset is not compatible with pendle market
        address invalidAsset = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        createAdapter();

        adapter.initialize(
            abi.encode(invalidAsset, address(this), strategy, 0, sigs, ""),
            address(pendleRouter),
            abi.encode(pendleMarket, pendleRouterStatic, swapDelay)
        );
    }
}
