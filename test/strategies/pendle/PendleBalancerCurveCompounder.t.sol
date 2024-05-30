// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";

import {IPendleRouter, IPendleSYToken, ISYTokenV3} from "../../../src/strategies/pendle/IPendle.sol";
import {PendleBalancerCurveCompounder, CurveSwap, IERC20, PendleDepositor} from "../../../src/strategies/pendle/PendleBalancerCurveCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson, Math} from "../BaseStrategyTest.sol";
import {TradePath, IAsset, BatchSwapStep} from "../../../src/peripheral/BaseBalancerCompounder.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PendleBalancerCurveCompounderTest is BaseStrategyTest {
    using stdJson for string;
    using Math for uint256;

    IPendleRouter pendleRouter =
        IPendleRouter(0x888888888889758F76e7103c6CbF23ABbF58F946);

    address balancerRouter =
        address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address curveRouter = address(0xF0d4c12A5768D806021F80a262B4d39d26C58b8D);

    address syToken;
    address pendleMarket;
    address pendleToken = address(0x808507121B80c02388fAd14726482e061B8da827);
    address WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address USDe = address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
    address pendleRouterStatic;
    address asset;

    PendleBalancerCurveCompounder strategyContract;

    function setUp() public {
        _setUpBaseTest(
            0,
            "./test/strategies/pendle/PendleBalancerCurveCompounderTestConfig.json"
        );
    }

    function _setUpStrategy(
        string memory json_,
        string memory index_,
        TestConfig memory testConfig_
    ) internal override returns (IBaseStrategy) {
        // Read strategy init values
        pendleMarket = json_.readAddress(
            string.concat(".configs[", index_, "].specific.init.pendleMarket")
        );
        pendleRouter = IPendleRouter(
            json_.readAddress(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.init.pendleRouter"
                )
            )
        );
        pendleRouterStatic = json_.readAddress(
            string.concat(
                ".configs[",
                index_,
                "].specific.init.pendleRouterStat"
            )
        );

        // Deploy Strategy
        PendleBalancerCurveCompounder strategy = new PendleBalancerCurveCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(pendleMarket, pendleRouter, pendleRouterStatic)
        );

        asset = strategy.asset();
        syToken = strategy.pendleSYToken();

        // Set Harvest values
        _setHarvestValues(json_, index_, payable(strategy));

        return IBaseStrategy(address(strategy));
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER
    //////////////////////////////////////////////////////////////*/

    function iouBalance() public view returns (uint256) {
        return IERC20(pendleMarket).balanceOf(address(strategy));
    }

    function increasePricePerShare(uint256 amount) public {
        deal(
            address(asset),
            address(pendleMarket),
            IERC20(address(asset)).balanceOf(address(pendleMarket)) + amount
        );
    }

    /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test__initialization() public override {
        string memory json = vm.readFile(
            "./test/strategies/pendle/PendleBalancerCurveCompounderTestConfig.json"
        );

        // Read strategy init values
        pendleMarket = json.readAddress(
            string.concat(".configs[0].specific.init.pendleMarket")
        );
        pendleRouter = IPendleRouter(
            json.readAddress(
                string.concat(".configs[0].specific.init.pendleRouter")
            )
        );
        pendleRouterStatic = json.readAddress(
            string.concat(".configs[0].specific.init.pendleRouterStat")
        );

        // Deploy Strategy
        PendleBalancerCurveCompounder strategy = new PendleBalancerCurveCompounder();

        strategy.initialize(
            asset,
            address(this),
            true,
            abi.encode(pendleMarket, pendleRouter, pendleRouterStatic)
        );

        assertEq(strategy.owner(), address(this), "owner");

        verify_strategyInit();
    }

    function test__maxDeposit() public override {
        uint256 maxDeposit = ISYTokenV3(syToken).supplyCap() -
            ISYTokenV3(syToken).totalSupply();

        assertEq(strategy.maxDeposit(bob), maxDeposit);

        // We need to deposit smth since pause tries to burn rETH which it cant if balance is 0
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);
        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        vm.prank(address(this));
        strategy.pause();

        assertEq(strategy.maxDeposit(bob), 0);
    }

    function test__previewWithdraw(uint8 fuzzAmount) public override {
        uint256 amount = bound(
            fuzzAmount,
            testConfig.minDeposit,
            testConfig.maxDeposit
        );

        /// Some strategies have slippage or rounding errors which makes `maWithdraw` lower than the deposit amount
        uint256 reqAssets = strategy.previewMint(
            strategy.previewWithdraw(amount)
        );

        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        amount = strategy.totalAssets();

        prop_previewWithdraw(bob, bob, bob, amount, testConfig.testId);
    }

    function test_depositWithdraw() public {
        assertEq(IERC20(pendleMarket).balanceOf(address(strategy)), 0);

        uint256 amount = 100 ether;
        deal(strategy.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(amount, bob);

        assertGt(IERC20(pendleMarket).balanceOf(address(strategy)), 0);
        uint256 totAssets = strategy.totalAssets();

        // remove partial amount
        uint256 shares = IERC20(address(strategy))
            .balanceOf(address(bob))
            .mulDiv(2e17, 1e18, Math.Rounding.Ceil);

        strategy.redeem(shares, bob, bob);
        assertEq(
            IERC20(strategy.asset()).balanceOf(bob),
            totAssets.mulDiv(2e17, 1e18, Math.Rounding.Floor)
        );

        // redeem whole amount
        strategy.redeem(IERC20(address(strategy)).balanceOf(bob), bob, bob);

        uint256 floating = IERC20(strategy.asset()).balanceOf(
            address(strategy)
        );

        assertEq(IERC20(pendleMarket).balanceOf(address(strategy)), 0);
        assertEq(floating, 0);
    }

    function test__harvest() public override {
        uint256 amount = 100 ether;
        deal(strategy.asset(), bob, amount);

        vm.startPrank(bob);
        IERC20(strategy.asset()).approve(address(strategy), type(uint256).max);
        strategy.deposit(amount, bob);
        vm.stopPrank();

        vm.roll(block.number + 1_000);
        vm.warp(block.timestamp + 15_000);

        uint256 totAssetsBefore = strategy.totalAssets();
        strategy.harvest(hex"");

        // total assets have increased
        assertGt(strategy.totalAssets(), totAssetsBefore);
    }

    function verify_strategyInit() public {
        assertEq(
            IERC20Metadata(address(strategy)).name(),
            string.concat(
                "VaultCraft Pendle ",
                IERC20Metadata(address(asset)).name(),
                " Adapter"
            ),
            "name"
        );
        assertEq(
            IERC20Metadata(address(strategy)).symbol(),
            string.concat("vcp-", IERC20Metadata(address(asset)).symbol()),
            "symbol"
        );

        assertEq(
            IERC20(asset).allowance(address(strategy), address(pendleRouter)),
            type(uint256).max,
            "allowance"
        );
    }

    function test_invalidToken() public {
        // Revert if asset is not compatible with pendle market
        address invalidAsset = address(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        // Deploy Strategy
        PendleBalancerCurveCompounder strategy = new PendleBalancerCurveCompounder();

        vm.expectRevert(PendleDepositor.InvalidAsset.selector);
        strategy.initialize(
            invalidAsset,
            address(this),
            true,
            abi.encode(pendleMarket, address(pendleRouter), pendleRouterStatic)
        );
    }

    function test_setHarvestValues_rerun() public {
        address[] memory oldRewards = strategy.rewardTokens();

        _setHarvestValues(json, "0", payable(address(strategy)));

        address[] memory newRewards = strategy.rewardTokens();

        assertEq(oldRewards.length, newRewards.length);
        assertEq(oldRewards[0], newRewards[0]);
    }

    function _setHarvestValues(
        string memory json_,
        string memory index_,
        address payable strategy
    ) internal {
        // Read harvest values
        address balancerVault_ = json_.readAddress(
            string.concat(
                ".configs[",
                index_,
                "].specific.harvest.balancerVault"
            )
        );

        TradePath[] memory tradePaths_ = _getTradePaths(json_, index_);

        address curveRouter_ = abi.decode(
            json_.parseRaw(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.curveRouter"
                )
            ),
            (address)
        );

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json_, index_);

        // Set harvest values
        PendleBalancerCurveCompounder(payable(strategy)).setHarvestValues(
            balancerVault_,
            tradePaths_,
            curveRouter,
            swaps_
        );
    }

    function _getTradePaths(
        string memory json_,
        string memory index_
    ) internal pure returns (TradePath[] memory) {
        uint256 swapLen = json_.readUint(
            string.concat(
                ".configs[",
                index_,
                "].specific.harvest.tradePaths.length"
            )
        );

        TradePath[] memory tradePaths_ = new TradePath[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory assetAddresses = json_.readAddressArray(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.tradePaths.structs[",
                    vm.toString(i),
                    "].assets"
                )
            );
            IAsset[] memory assets = new IAsset[](assetAddresses.length);
            for (uint256 n; n < assetAddresses.length; n++) {
                assets[n] = IAsset(assetAddresses[n]);
            }

            int256[] memory limits = json_.readIntArray(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.tradePaths.structs[",
                    vm.toString(i),
                    "].limits"
                )
            );

            BatchSwapStep[] memory swapSteps = abi.decode(
                json_.parseRaw(
                    string.concat(
                        ".configs[",
                        index_,
                        "].specific.harvest.tradePaths.structs[",
                        vm.toString(i),
                        "].swaps"
                    )
                ),
                (BatchSwapStep[])
            );

            tradePaths_[i] = TradePath({
                assets: assets,
                limits: limits,
                swaps: abi.encode(swapSteps)
            });
        }

        return tradePaths_;
    }

    function _getCurveSwaps(
        string memory json_,
        string memory index_
    ) internal pure returns (CurveSwap[] memory) {
        uint256 swapLen = json_.readUint(
            string.concat(
                ".configs[",
                index_,
                "].specific.harvest.swaps.length"
            )
        );

        CurveSwap[] memory swaps_ = new CurveSwap[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory route_ = json_.readAddressArray(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.swaps.structs[",
                    vm.toString(i),
                    "].route"
                )
            );
            address[11] memory route;
            for (uint256 n; n < 11; n++) {
                route[n] = route_[n];
            }

            // Read swapParams and convert dynamic into fixed size array
            uint256[5][5] memory swapParams;
            for (uint256 n = 0; n < 5; n++) {
                uint256[] memory swapParams_ = json_.readUintArray(
                    string.concat(
                        ".configs[",
                        index_,
                        "].specific.harvest.swaps.structs[",
                        vm.toString(i),
                        "].swapParams[",
                        vm.toString(n),
                        "]"
                    )
                );
                for (uint256 y; y < 5; y++) {
                    swapParams[n][y] = swapParams_[y];
                }
            }

            // Read pools and convert dynamic into fixed size array
            address[] memory pools_ = json_.readAddressArray(
                string.concat(
                    ".configs[",
                    index_,
                    "].specific.harvest.swaps.structs[",
                    vm.toString(i),
                    "].pools"
                )
            );
            address[5] memory pools;
            for (uint256 n = 0; n < 5; n++) {
                pools[n] = pools_[n];
            }

            // Construct the struct
            swaps_[i] = CurveSwap({
                route: route,
                swapParams: swapParams,
                pools: pools
            });
        }
        return swaps_;
    }
}
