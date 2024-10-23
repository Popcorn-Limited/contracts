// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IPendleRouter, IPendleSYToken} from "src/strategies/pendle/IPendle.sol";
import {PendleBalancerCompounder, PendleDepositor} from "src/strategies/pendle/PendleBalancerCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import {TradePath, IAsset, BatchSwapStep} from "src/peripheral/compounder/balancer/BaseBalancerCompounder.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PendleBalancerCompounderTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IPendleRouter pendleRouter;
    address balancerRouter = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    IPendleSYToken synToken;
    address pendleMarket;
    address pendleToken = address(0x808507121B80c02388fAd14726482e061B8da827);
    address WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address pendleRouterStatic;
    address asset;

    PendleBalancerCompounder strategyContract;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/pendle/PendleBalancerCompounderTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        pendleMarket = json_.readAddress(string.concat(".configs[", index_, "].specific.init.pendleMarket"));
        pendleRouter =
            IPendleRouter(json_.readAddress(string.concat(".configs[", index_, "].specific.init.pendleRouter")));
        pendleRouterStatic = json_.readAddress(string.concat(".configs[", index_, "].specific.init.pendleRouterStat"));

        // Deploy Strategy
        PendleBalancerCompounder strategy = new PendleBalancerCompounder();

        strategy.initialize(
            testConfig_.asset, address(this), true, abi.encode(pendleMarket, pendleRouter, pendleRouterStatic)
        );

        // Set Harvest values
        _setHarvestValues(json_, index_, payable(strategy));

        asset = strategy.asset();

        return IBaseStrategy(address(strategy));
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function iouBalance() public view returns (uint256) {
        return IERC20(pendleMarket).balanceOf(address(strategy));
    }

    function increasePricePerShare(uint256 amount) public {
        deal(address(asset), address(pendleMarket), IERC20(address(asset)).balanceOf(address(pendleMarket)) + amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        string memory json = vm.readFile("./test/strategies/pendle/PendleBalancerCompounderTestConfig.json");

        // Read strategy init values
        pendleMarket = json.readAddress(string.concat(".configs[0].specific.init.pendleMarket"));
        pendleRouter = IPendleRouter(json.readAddress(string.concat(".configs[0].specific.init.pendleRouter")));
        pendleRouterStatic = json.readAddress(string.concat(".configs[0].specific.init.pendleRouterStat"));

        // Deploy Strategy
        PendleBalancerCompounder strategy = new PendleBalancerCompounder();

        strategy.initialize(asset, address(this), true, abi.encode(pendleMarket, pendleRouter, pendleRouterStatic));

        assertEq(strategy.owner(), address(this), "owner");

        verify_strategyInit();
    }

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        /// Some strategies have slippage or rounding errors which makes `maWithdraw` lower than the deposit amount
        uint256 reqAssets = strategy.previewMint(strategy.previewWithdraw(amount));

        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        amount = strategy.totalAssets();

        prop_previewWithdraw(bob, bob, bob, amount, testConfig.testId);
    }

    function test_depositWithdraw() public {
        assertEq(IERC20(pendleMarket).balanceOf(address(strategy)), 0);

        uint256 amount = 1 ether;
        deal(strategy.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(amount, bob);

        assertGt(IERC20(pendleMarket).balanceOf(address(strategy)), 0);
        uint256 totAssets = strategy.totalAssets();

        strategy.redeem(IERC20(address(strategy)).balanceOf(address(bob)), bob, bob);
        vm.stopPrank();

        assertEq(IERC20(pendleMarket).balanceOf(address(strategy)), 0);
        assertEq(IERC20(strategy.asset()).balanceOf(bob), totAssets);
    }

    function test__harvest() public override {
        uint256 amount = 1 ether;
        deal(strategy.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(amount, bob);
        vm.stopPrank();

        vm.roll(block.number + 1_000_00);
        vm.warp(block.timestamp + 1_500_000);

        uint256 totAssetsBefore = strategy.totalAssets();

        strategy.harvest(hex"");

        // total assets have increased
        assertGt(strategy.totalAssets(), totAssetsBefore);
    }

    function verify_strategyInit() public {
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat("VaultCraft Pendle ", IERC20Metadata(address(asset)).name(), " Adapter"),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vcp-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(IERC20(asset).allowance(address(strategy), address(pendleRouter)), type(uint256).max, "allowance");
    }

    function test_invalidToken() public {
        // Revert if asset is not compatible with pendle market
        address invalidAsset = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        // Deploy Strategy
        PendleBalancerCompounder strategy = new PendleBalancerCompounder();

        vm.expectRevert(PendleDepositor.InvalidAsset.selector);
        strategy.initialize(
            invalidAsset, address(this), true, abi.encode(pendleMarket, address(pendleRouter), pendleRouterStatic)
        );
    }

    function test_setHarvestValues_rerun() public {
        address[] memory oldRewards = strategy.rewardTokens();

        _setHarvestValues(json, "0", payable(address(strategy)));

        address[] memory newRewards = strategy.rewardTokens();

        assertEq(oldRewards.length, newRewards.length);
        assertEq(oldRewards[0], newRewards[0]);
    }

    function _setHarvestValues(string memory json_, string memory index_, address payable strategy) internal {
        // Read harvest values
        address balancerVault_ =
            json_.readAddress(string.concat(".configs[", index_, "].specific.harvest.balancerVault"));

        TradePath[] memory tradePaths_ = _getTradePaths(json_, index_);

        // Set harvest values
        PendleBalancerCompounder(payable(strategy)).setHarvestValues(balancerVault_, tradePaths_);
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
}
