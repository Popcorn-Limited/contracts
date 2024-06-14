// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.25

pragma solidity ^0.8.25;

import {
    CurveGaugeSingleAssetCompounder,
    IERC20,
    CurveSwap
} from "../../../src/strategies/curve/CurveGaugeSingleAssetCompounder.sol";
import {BaseStrategyTest, IBaseStrategy, TestConfig, stdJson} from "../BaseStrategyTest.sol";

struct CurveGaugeInit {
    address gauge;
    int128 indexIn;
    address lpToken;
    address pool;
}

contract CurveGaugeSingleAssetCompounderTest is BaseStrategyTest {
    using stdJson for string;

    function setUp() public {
        _setUpBaseTest(0, "./test/strategies/curve/CurveGaugeSingleAssetCompounderTestConfig.json");
    }

    function _setUpStrategy(string memory json_, string memory index_, TestConfig memory testConfig_)
        internal
        override
        returns (IBaseStrategy)
    {
        // Read strategy init values
        CurveGaugeInit memory curveInit =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.init")), (CurveGaugeInit));

        // Deploy Strategy
        CurveGaugeSingleAssetCompounder strategy = new CurveGaugeSingleAssetCompounder();

        strategy.initialize(
            testConfig_.asset,
            address(this),
            true,
            abi.encode(curveInit.lpToken, curveInit.pool, curveInit.gauge, curveInit.indexIn)
        );

        // Set Harvest values
        _setHarvestValues(json_, index_, address(strategy));

        return IBaseStrategy(address(strategy));
    }

    function _setHarvestValues(string memory json_, string memory index_, address strategy) internal {
        // Read harvest values
        address curveRouter_ =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.harvest.curveRouter")), (address));

        //Construct CurveSwap structs
        CurveSwap[] memory swaps_ = _getCurveSwaps(json_, index_);

        uint256 slippage_ =
            abi.decode(json_.parseRaw(string.concat(".configs[", index_, "].specific.harvest.slippage")), (uint256));

        // Set harvest values
        CurveGaugeSingleAssetCompounder(strategy).setHarvestValues(curveRouter_, swaps_, slippage_);
    }

    function _getCurveSwaps(string memory json_, string memory index_) internal pure returns (CurveSwap[] memory) {
        uint256 swapLen = json_.readUint(string.concat(".configs[", index_, "].specific.harvest.swaps.length"));

        CurveSwap[] memory swaps_ = new CurveSwap[](swapLen);
        for (uint256 i; i < swapLen; i++) {
            // Read route and convert dynamic into fixed size array
            address[] memory route_ = json_.readAddressArray(
                string.concat(".configs[", index_, "].specific.harvest.swaps.structs[", vm.toString(i), "].route")
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
                string.concat(".configs[", index_, "].specific.harvest.swaps.structs[", vm.toString(i), "].pools")
            );
            address[5] memory pools;
            for (uint256 n = 0; n < 5; n++) {
                pools[n] = pools_[n];
            }

            // Construct the struct
            swaps_[i] = CurveSwap({route: route, swapParams: swapParams, pools: pools});
        }
        return swaps_;
    }

    // function _increasePricePerShare(uint256 amount) internal override {
    //     address aToken = address(AaveV3Depositor(address(strategy)).aToken());
    //     deal(
    //         testConfig.asset,
    //         aToken,
    //         IERC20(testConfig.asset).balanceOf(aToken) + amount
    //     );
    // }

    /*//////////////////////////////////////////////////////////////
                            OVERRIDEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test__previewRedeem(uint8 fuzzAmount) public override {
        uint256 amount = bound(fuzzAmount, testConfig.minDeposit, testConfig.maxDeposit);

        uint256 reqAssets = strategy.previewMint(strategy.previewRedeem(amount)) + 10;
        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        prop_previewRedeem(bob, bob, bob, amount, testConfig.testId);
    }

    function test__deposit_autoDeposit_off() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        assertEq(strategy.totalAssets(), testConfig.defaultAmount, "ta");
        assertEq(strategy.totalSupply(), testConfig.defaultAmount - testConfig.delta, "ts");
        assertEq(strategy.balanceOf(bob), testConfig.defaultAmount - testConfig.delta, "share bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount, "strategy asset bal");
    }

    function test__mint_autoDeposit_off() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        assertEq(strategy.totalAssets(), testConfig.defaultAmount, "ta");
        assertEq(strategy.totalSupply(), testConfig.defaultAmount - testConfig.delta, "ts");
        assertEq(strategy.balanceOf(bob), testConfig.defaultAmount - testConfig.delta, "share bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), testConfig.defaultAmount, "strategy asset bal");
    }

    function test__withdraw_autoDeposit_off() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.startPrank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        strategy.withdraw(strategy.previewRedeem(strategy.balanceOf(bob)), bob, bob);
        vm.stopPrank();

        // @dev rounding issues fuck these numbers up by 1 wei
        assertEq(strategy.totalAssets(), 1, "ta");
        assertEq(strategy.totalSupply(), 0, "ts");
        assertEq(strategy.balanceOf(bob), 0, "share bal");
        assertEq(IERC20(_asset_).balanceOf(bob), testConfig.defaultAmount - 1, "asset bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), 1, "strategy asset bal");
    }

    function test__redeem_autoDeposit_off() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.startPrank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        strategy.redeem(strategy.balanceOf(bob), bob, bob);
        vm.stopPrank();

        // @dev rounding issues fuck these numbers up by 1 wei
        assertEq(strategy.totalAssets(), 1, "ta");
        assertEq(strategy.totalSupply(), 0, "ts");
        assertEq(strategy.balanceOf(bob), 0, "share bal");
        assertEq(IERC20(_asset_).balanceOf(bob), testConfig.defaultAmount - 1, "asset bal");
        assertEq(IERC20(_asset_).balanceOf(address(strategy)), 1, "strategy asset bal");
    }

    /// @dev Partially withdraw assets directly from strategy and the underlying protocol
    function test__withdraw_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();

        uint256 reqAssets = (testConfig.defaultAmount * 10) / 10;
        _mintAssetAndApproveForStrategy(reqAssets, bob);

        vm.prank(bob);
        strategy.deposit(reqAssets, bob);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds((testConfig.defaultAmount / 5) * 2, bytes(""));

        // Withdraw 80% of deposit
        vm.prank(bob);
        strategy.withdraw((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, 96442893003781, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, 1132742627023746, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, 1132742627023746, "share bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, _delta_, "asset bal");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    /// @dev Partially redeem assets directly from strategy and the underlying protocol
    function test__redeem_autoDeposit_partial() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        // Push 40% the funds into the underlying protocol
        strategy.pushFunds((testConfig.defaultAmount / 5) * 2, bytes(""));

        // Redeem 80% of deposit
        vm.prank(bob);
        strategy.redeem((testConfig.defaultAmount / 5) * 4, bob, bob);

        assertApproxEqAbs(strategy.totalAssets(), testConfig.defaultAmount / 5, 3981119898726623, "ta");
        assertApproxEqAbs(strategy.totalSupply(), testConfig.defaultAmount / 5, _delta_, "ts");
        assertApproxEqAbs(strategy.balanceOf(bob), testConfig.defaultAmount / 5, _delta_, "share bal");
        assertApproxEqAbs(
            IERC20(_asset_).balanceOf(bob), (testConfig.defaultAmount / 5) * 4, 3886042782479058, "asset bal"
        );
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    function test__pushFunds() public override {
        strategy.toggleAutoDeposit();
        _mintAssetAndApproveForStrategy(testConfig.defaultAmount, bob);

        vm.prank(bob);
        strategy.deposit(testConfig.defaultAmount, bob);

        uint256 oldTa = strategy.totalAssets();
        uint256 oldTs = strategy.totalSupply();

        strategy.pushFunds(testConfig.defaultAmount, bytes(""));

        assertApproxEqAbs(strategy.totalAssets(), oldTa, 416835800279253, "ta");
        assertApproxEqAbs(strategy.totalSupply(), oldTs, _delta_, "ts");
        assertApproxEqAbs(IERC20(_asset_).balanceOf(address(strategy)), 0, _delta_, "strategy asset bal");
    }

    /*//////////////////////////////////////////////////////////////
                                HARVEST
    //////////////////////////////////////////////////////////////*/

    function test__harvest() public override {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.warp(block.timestamp + 150_000);

        strategy.harvest(abi.encode(uint256(0)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_slippage_too_high() public {
        _mintAssetAndApproveForStrategy(10000e18, bob);

        vm.prank(bob);
        strategy.deposit(10000e18, bob);

        uint256 oldTa = strategy.totalAssets();

        vm.warp(block.timestamp + 150_000);

        strategy.harvest(abi.encode(uint256(5530379817425055987)));

        assertGt(strategy.totalAssets(), oldTa);
    }

    function testFail__harvest_no_rewards() public {
        _mintAssetAndApproveForStrategy(100e18, bob);

        vm.prank(bob);
        strategy.deposit(100e18, bob);

        uint256 oldTa = strategy.totalAssets();

        strategy.harvest(abi.encode(uint256(6e18)));

        assertEq(strategy.totalAssets(), oldTa);
    }
}
